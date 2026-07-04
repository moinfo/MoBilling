<?php

namespace App\Http\Controllers;

use App\Models\ConfigOption;
use App\Models\ConfigOptionChoice;
use App\Models\ConfigOptionGroup;
use App\Models\ProductService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

/**
 * Admin CRUD for configurable option groups (WHMCS-parity). A group bundles
 * options (dropdown/radio/yesno/quantity) with priced choices; groups attach to
 * products and clients configure them at order time. Selected options are billed
 * on the order + recurring renewal invoices.
 */
class ConfigOptionGroupController extends Controller
{
    public function index(Request $request)
    {
        $query = ConfigOptionGroup::with(['options.choices', 'products:id,name'])->orderBy('name');

        if ($request->boolean('active_only', false)) {
            $query->active();
        }

        if ($request->filled('search')) {
            $query->where('name', 'like', "%{$request->search}%");
        }

        return response()->json([
            'data' => $query->get()->map(fn ($g) => $this->present($g)),
        ]);
    }

    public function store(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;
        $data = $this->validateData($request, $tenantId);

        $group = DB::transaction(function () use ($data, $tenantId) {
            $group = ConfigOptionGroup::create([
                'name'        => $data['name'],
                'description' => $data['description'] ?? null,
                'is_active'   => $data['is_active'] ?? true,
            ]);

            $this->syncOptions($group, $data['options'] ?? [], $tenantId);
            $group->products()->sync($this->syncPayload($data['product_service_ids'] ?? [], $tenantId));

            return $group;
        });

        return response()->json(['data' => $this->present($this->reload($group))], 201);
    }

    public function update(Request $request, ConfigOptionGroup $configOptionGroup)
    {
        $tenantId = auth()->user()->tenant_id;
        $data = $this->validateData($request, $tenantId);

        DB::transaction(function () use ($configOptionGroup, $data, $tenantId) {
            $configOptionGroup->update([
                'name'        => $data['name'],
                'description' => $data['description'] ?? null,
                'is_active'   => $data['is_active'] ?? true,
            ]);

            if (array_key_exists('options', $data)) {
                $this->syncOptions($configOptionGroup, $data['options'] ?? [], $tenantId);
            }

            if (array_key_exists('product_service_ids', $data)) {
                $configOptionGroup->products()->sync($this->syncPayload($data['product_service_ids'], $tenantId));
            }
        });

        return response()->json(['data' => $this->present($this->reload($configOptionGroup))]);
    }

    public function destroy(ConfigOptionGroup $configOptionGroup)
    {
        $configOptionGroup->delete();
        return response()->json(['message' => 'Deleted successfully']);
    }

    /**
     * Upsert the group's options and their choices, deleting any that were
     * removed from the payload. Runs inside the caller's transaction.
     */
    private function syncOptions(ConfigOptionGroup $group, array $options, string $tenantId): void
    {
        $keptOptionIds = [];

        foreach ($options as $opt) {
            $type = $opt['option_type'];
            $hasChoices = in_array($type, ['dropdown', 'radio']);

            $model = ConfigOption::updateOrCreate(
                [
                    'id'                     => $opt['id'] ?? null,
                    'config_option_group_id' => $group->id,
                ],
                [
                    'tenant_id'  => $tenantId,
                    'name'       => $opt['name'],
                    'option_type' => $type,
                    'unit_price' => $hasChoices ? null : ($opt['unit_price'] ?? 0),
                    'sort_order' => $opt['sort_order'] ?? 0,
                ]
            );
            $keptOptionIds[] = $model->id;

            $keptChoiceIds = [];
            if ($hasChoices) {
                foreach ($opt['choices'] ?? [] as $choice) {
                    $choiceModel = ConfigOptionChoice::updateOrCreate(
                        [
                            'id'               => $choice['id'] ?? null,
                            'config_option_id' => $model->id,
                        ],
                        [
                            'tenant_id'  => $tenantId,
                            'label'      => $choice['label'],
                            'price'      => $choice['price'] ?? 0,
                            'sort_order' => $choice['sort_order'] ?? 0,
                        ]
                    );
                    $keptChoiceIds[] = $choiceModel->id;
                }
            }

            // Remove choices dropped from the payload (or all, for non-choice types).
            ConfigOptionChoice::where('config_option_id', $model->id)
                ->whereNotIn('id', $keptChoiceIds)
                ->delete();
        }

        // Remove options dropped from the payload.
        ConfigOption::where('config_option_group_id', $group->id)
            ->whereNotIn('id', $keptOptionIds)
            ->each(function ($opt) {
                ConfigOptionChoice::where('config_option_id', $opt->id)->delete();
                $opt->delete();
            });
    }

    private function validateData(Request $request, string $tenantId): array
    {
        return $request->validate([
            'name'        => 'required|string|max:255',
            'description' => 'nullable|string',
            'is_active'   => 'boolean',

            'product_service_ids'   => 'nullable|array',
            'product_service_ids.*' => ['uuid',
                Rule::exists('product_services', 'id')->where('tenant_id', $tenantId)],

            'options'                    => 'nullable|array',
            'options.*.id'               => ['nullable', 'uuid',
                Rule::exists('config_options', 'id')->where('tenant_id', $tenantId)],
            'options.*.name'             => 'required|string|max:255',
            'options.*.option_type'      => ['required', Rule::in(['dropdown', 'radio', 'yesno', 'quantity'])],
            'options.*.unit_price'       => 'nullable|numeric|min:0',
            'options.*.sort_order'       => 'nullable|integer',
            'options.*.choices'          => 'nullable|array',
            'options.*.choices.*.id'     => ['nullable', 'uuid',
                Rule::exists('config_option_choices', 'id')->where('tenant_id', $tenantId)],
            'options.*.choices.*.label'  => 'required|string|max:255',
            'options.*.choices.*.price'  => 'nullable|numeric|min:0',
            'options.*.choices.*.sort_order' => 'nullable|integer',
        ]);
    }

    /**
     * Build the belongsToMany sync payload, keeping only tenant-owned products
     * and stamping the pivot tenant_id.
     */
    private function syncPayload(array $ids, string $tenantId): array
    {
        if (empty($ids)) {
            return [];
        }

        return ProductService::whereIn('id', $ids)
            ->where('tenant_id', $tenantId)
            ->pluck('id')
            ->mapWithKeys(fn ($id) => [$id => ['tenant_id' => $tenantId]])
            ->all();
    }

    private function reload(ConfigOptionGroup $group): ConfigOptionGroup
    {
        return $group->fresh(['options.choices', 'products:id,name']);
    }

    private function present(ConfigOptionGroup $group): array
    {
        return [
            'id'          => $group->id,
            'name'        => $group->name,
            'description' => $group->description,
            'is_active'   => $group->is_active,
            'product_service_ids' => $group->products->pluck('id')->values(),
            'products'    => $group->products->map(fn ($p) => ['id' => $p->id, 'name' => $p->name])->values(),
            'options'     => $group->options->map(fn ($o) => [
                'id'          => $o->id,
                'name'        => $o->name,
                'option_type' => $o->option_type,
                'unit_price'  => $o->unit_price !== null ? (float) $o->unit_price : null,
                'sort_order'  => $o->sort_order,
                'choices'     => $o->choices->map(fn ($c) => [
                    'id'         => $c->id,
                    'label'      => $c->label,
                    'price'      => (float) $c->price,
                    'sort_order' => $c->sort_order,
                ])->values(),
            ])->values(),
        ];
    }
}

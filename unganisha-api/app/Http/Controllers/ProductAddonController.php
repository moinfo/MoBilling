<?php

namespace App\Http\Controllers;

use App\Models\ProductAddon;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Admin CRUD for paid product add-ons (WHMCS-parity upsell). Add-ons are
 * attached to hosting products; clients pick them at order time and they are
 * billed on the order + recurring renewal invoices.
 */
class ProductAddonController extends Controller
{
    public function index(Request $request)
    {
        $query = ProductAddon::with('products:id,name')->orderBy('name');

        if ($request->boolean('active_only', false)) {
            $query->active();
        }

        if ($request->filled('search')) {
            $query->where('name', 'like', "%{$request->search}%");
        }

        return response()->json([
            'data' => $query->get()->map(fn ($a) => $this->present($a)),
        ]);
    }

    public function store(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;
        $data = $this->validateData($request, $tenantId);

        $addon = ProductAddon::create(collect($data)->except('product_service_ids')->toArray());
        $addon->products()->sync($this->syncPayload($data['product_service_ids'] ?? [], $tenantId));

        return response()->json(['data' => $this->present($addon->load('products:id,name'))], 201);
    }

    public function update(Request $request, ProductAddon $productAddon)
    {
        $tenantId = auth()->user()->tenant_id;
        $data = $this->validateData($request, $tenantId);

        $productAddon->update(collect($data)->except('product_service_ids')->toArray());

        if (array_key_exists('product_service_ids', $data)) {
            $productAddon->products()->sync($this->syncPayload($data['product_service_ids'], $tenantId));
        }

        return response()->json(['data' => $this->present($productAddon->fresh()->load('products:id,name'))]);
    }

    public function destroy(ProductAddon $productAddon)
    {
        $productAddon->delete();
        return response()->json(['message' => 'Deleted successfully']);
    }

    private function validateData(Request $request, string $tenantId): array
    {
        return $request->validate([
            'name'          => 'required|string|max:255',
            'description'   => 'nullable|string',
            'price'         => 'required|numeric|min:0',
            'billing_cycle' => ['required', Rule::in(['once', 'monthly', 'quarterly', 'half_yearly', 'yearly'])],
            'tax_percent'   => 'nullable|numeric|min:0|max:100',
            'is_active'     => 'boolean',
            'product_service_ids'   => 'nullable|array',
            'product_service_ids.*' => ['uuid',
                Rule::exists('product_services', 'id')->where('tenant_id', $tenantId)],
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

        return \App\Models\ProductService::whereIn('id', $ids)
            ->where('tenant_id', $tenantId)
            ->pluck('id')
            ->mapWithKeys(fn ($id) => [$id => ['tenant_id' => $tenantId]])
            ->all();
    }

    private function present(ProductAddon $addon): array
    {
        return [
            'id'            => $addon->id,
            'name'          => $addon->name,
            'description'   => $addon->description,
            'price'         => (float) $addon->price,
            'billing_cycle' => $addon->billing_cycle,
            'tax_percent'   => (float) $addon->tax_percent,
            'is_active'     => $addon->is_active,
            'product_service_ids' => $addon->products->pluck('id')->values(),
            'products'      => $addon->products->map(fn ($p) => ['id' => $p->id, 'name' => $p->name])->values(),
        ];
    }
}

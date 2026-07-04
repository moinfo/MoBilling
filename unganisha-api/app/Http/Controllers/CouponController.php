<?php

namespace App\Http\Controllers;

use App\Models\Coupon;
use App\Models\ProductService;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Admin CRUD for promotions / coupon codes (WHMCS-parity). Tenant-scoped;
 * gated on products.* permissions like the other catalog features.
 */
class CouponController extends Controller
{
    public function index(Request $request)
    {
        $query = Coupon::with('products:id,name')
            ->withCount('redemptions')
            ->withMax('redemptions', 'created_at')
            ->orderBy('code');

        if ($request->boolean('active_only', false)) {
            $query->active();
        }

        if ($request->filled('search')) {
            $query->where('code', 'like', '%' . strtoupper($request->search) . '%');
        }

        return response()->json([
            'data' => $query->get()->map(fn ($c) => $this->present($c)),
        ]);
    }

    public function store(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;
        $data = $this->validateData($request, $tenantId, null);

        $coupon = Coupon::create(collect($data)->except('product_service_ids')->toArray());
        $coupon->products()->sync($this->syncPayload($data['product_service_ids'] ?? [], $tenantId));

        return response()->json(['data' => $this->present($coupon->fresh()->loadCount('redemptions')->load('products:id,name'))], 201);
    }

    public function update(Request $request, Coupon $coupon)
    {
        $tenantId = auth()->user()->tenant_id;
        $data = $this->validateData($request, $tenantId, $coupon->id);

        $coupon->update(collect($data)->except('product_service_ids')->toArray());

        if (array_key_exists('product_service_ids', $data)) {
            $coupon->products()->sync($this->syncPayload($data['product_service_ids'], $tenantId));
        }

        return response()->json(['data' => $this->present($coupon->fresh()->loadCount('redemptions')->load('products:id,name'))]);
    }

    public function destroy(Coupon $coupon)
    {
        $coupon->delete();
        return response()->json(['message' => 'Deleted successfully']);
    }

    /** Attach products this coupon applies to (only meaningful when applies_to=product). */
    public function attachProducts(Request $request, Coupon $coupon)
    {
        $tenantId = auth()->user()->tenant_id;
        $data = $request->validate([
            'product_service_ids'   => 'required|array',
            'product_service_ids.*' => ['uuid', Rule::exists('product_services', 'id')->where('tenant_id', $tenantId)],
        ]);

        $coupon->products()->syncWithoutDetaching($this->syncPayload($data['product_service_ids'], $tenantId));

        return response()->json(['data' => $this->present($coupon->fresh()->loadCount('redemptions')->load('products:id,name'))]);
    }

    public function detachProduct(Coupon $coupon, string $productServiceId)
    {
        $coupon->products()->detach($productServiceId);

        return response()->json(['data' => $this->present($coupon->fresh()->loadCount('redemptions')->load('products:id,name'))]);
    }

    /** Redemption history for a coupon (audit / who used it). */
    public function redemptions(Coupon $coupon)
    {
        $rows = $coupon->redemptions()
            ->with('client:id,name')
            ->latest()
            ->limit(200)
            ->get()
            ->map(fn ($r) => [
                'id'              => $r->id,
                'client_id'       => $r->client_id,
                'client_name'     => $r->client?->name,
                'document_id'     => $r->document_id,
                'discount_amount' => (float) $r->discount_amount,
                'created_at'      => $r->created_at,
            ]);

        return response()->json(['data' => $rows]);
    }

    private function validateData(Request $request, string $tenantId, ?string $couponId): array
    {
        return $request->validate([
            // No whereNull('deleted_at'): the DB unique index (tenant_id, code)
            // spans soft-deleted rows too, so a deleted code stays reserved.
            'code'        => ['required', 'string', 'max:64',
                Rule::unique('coupons', 'code')
                    ->where('tenant_id', $tenantId)
                    ->ignore($couponId)],
            'description' => 'nullable|string|max:255',
            'type'        => ['required', Rule::in(['percent', 'fixed'])],
            'value'       => 'required|numeric|min:0',
            'applies_to'  => ['required', Rule::in(['all', 'product'])],
            'max_uses'    => 'nullable|integer|min:1',
            'min_order'   => 'nullable|numeric|min:0',
            'starts_at'   => 'nullable|date',
            'expires_at'  => 'nullable|date|after_or_equal:starts_at',
            'recurring'   => 'boolean',
            'is_active'   => 'boolean',
            'product_service_ids'   => 'nullable|array',
            'product_service_ids.*' => ['uuid', Rule::exists('product_services', 'id')->where('tenant_id', $tenantId)],
        ]);
    }

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

    private function present(Coupon $coupon): array
    {
        return [
            'id'          => $coupon->id,
            'code'        => $coupon->code,
            'description' => $coupon->description,
            'type'        => $coupon->type,
            'value'       => (float) $coupon->value,
            'applies_to'  => $coupon->applies_to,
            'max_uses'    => $coupon->max_uses,
            'uses'        => (int) $coupon->uses,
            'min_order'   => $coupon->min_order !== null ? (float) $coupon->min_order : null,
            'starts_at'   => optional($coupon->starts_at)->toIso8601String(),
            'expires_at'  => optional($coupon->expires_at)->toIso8601String(),
            'recurring'   => (bool) $coupon->recurring,
            'is_active'   => (bool) $coupon->is_active,
            'redemptions_count' => $coupon->redemptions_count ?? (int) $coupon->uses,
            'last_used_at'      => $coupon->redemptions_max_created_at ?? null,
            'product_service_ids' => $coupon->products->pluck('id')->values(),
            'products'    => $coupon->products->map(fn ($p) => ['id' => $p->id, 'name' => $p->name])->values(),
        ];
    }
}

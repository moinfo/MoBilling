<?php

namespace App\Http\Controllers;

use App\Http\Requests\StoreProductServiceRequest;
use App\Http\Resources\ProductServiceResource;
use App\Models\ClientSubscription;
use App\Models\ProductService;
use App\Models\Tenant;
use Illuminate\Http\Request;

class ProductServiceController extends Controller
{
    /**
     * A product duplicated onto a wallet-gated reseller tenant at
     * provisioning (managed_by_platform) is real shared infrastructure they
     * never set up themselves — editing it (any field, not just the
     * provisioning ones) or deleting it outright is staff-only. Their own
     * price margin on these is set through the dedicated bulkMargin() tool
     * instead, which only ever writes price = cost_price + margin. A
     * product they create themselves has managed_by_platform = false and is
     * fully theirs to manage.
     */
    private function assertEditable(ProductService $p): void
    {
        if (!$p->managed_by_platform) {
            return;
        }
        $walletGated = (bool) Tenant::withoutGlobalScopes()->find(auth()->user()->tenant_id)?->is_wallet_gated;
        abort_if($walletGated, 403, 'This product is managed for you — use "Set your profit margin" to adjust its price, or contact support for anything else.');
    }

    public function index(Request $request)
    {
        // Lets staff spot true duplicates (never subscribed) vs. legacy price
        // variants a real client is still on — see Discover Hosting Accounts'
        // WHM-package matching, which surfaced how tangled these got in the
        // WHMCS import.
        $query = ProductService::query()
            ->withCount([
                'subscriptions',
                'subscriptions as active_subscriptions_count' => fn ($q) => $q->where('status', 'active'),
            ])
            ->addSelect(['clients_count' => ClientSubscription::selectRaw('COUNT(DISTINCT client_id)')
                ->whereColumn('product_service_id', 'product_services.id')
            ]);

        if ($request->has('type')) {
            $query->where('type', $request->type);
        }

        if ($request->has('search')) {
            $search = $request->search;
            $query->where(function ($q) use ($search) {
                $q->where('name', 'LIKE', "%{$search}%")
                  ->orWhere('code', 'LIKE', "%{$search}%");
            });
        }

        if ($request->boolean('active_only', false)) {
            $query->active();
        }

        return ProductServiceResource::collection(
            $query->orderBy('name')->paginate($request->per_page ?? 20)
        );
    }

    public function store(StoreProductServiceRequest $request)
    {
        $productService = ProductService::create($request->validated());
        return new ProductServiceResource($productService);
    }

    public function show(ProductService $productService)
    {
        return new ProductServiceResource($productService);
    }

    public function update(StoreProductServiceRequest $request, ProductService $productService)
    {
        $this->assertEditable($productService);
        $productService->update($request->validated());
        return new ProductServiceResource($productService);
    }

    public function destroy(ProductService $productService)
    {
        $this->assertEditable($productService);
        $productService->delete();
        return response()->json(['message' => 'Deleted successfully']);
    }

    public function products(Request $request)
    {
        $request->merge(['type' => 'product']);
        return $this->index($request);
    }

    public function services(Request $request)
    {
        $request->merge(['type' => 'service']);
        return $this->index($request);
    }

    /**
     * Set the retail price on every one of the tenant's own hosting/email
     * products to "my real cost + this margin" in one go — same convenience
     * as DomainTldController::bulkMargin(), for a wallet-gated reseller whose
     * hosting/email products start out priced exactly at cost (no margin)
     * when provisioned. cost_price is $hidden on the model and never
     * returned to the client — only used here, server-side, to compute the
     * new price. A product with no cost_price set has nothing to add a
     * margin to, so it's left alone and counted in `skipped`.
     */
    public function bulkMargin(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;
        $data = $request->validate(['margin' => 'required|numeric|min:0']);

        $rows = ProductService::where('tenant_id', $tenantId)
            ->where('type', 'product')->where('is_active', true)->get();
        $updated = 0;
        $skipped = 0;

        foreach ($rows as $row) {
            if ($row->cost_price === null) {
                $skipped++;
                continue;
            }
            $row->update(['price' => round((float) $row->cost_price + $data['margin'], 2)]);
            $updated++;
        }

        return response()->json(['updated' => $updated, 'skipped' => $skipped]);
    }
}

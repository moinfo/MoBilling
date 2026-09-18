<?php

namespace App\Http\Controllers;

use App\Http\Requests\StoreProductServiceRequest;
use App\Http\Resources\ProductServiceResource;
use App\Models\ClientSubscription;
use App\Models\ProductService;
use Illuminate\Http\Request;

class ProductServiceController extends Controller
{
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
        $productService->update($request->validated());
        return new ProductServiceResource($productService);
    }

    public function destroy(ProductService $productService)
    {
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
}

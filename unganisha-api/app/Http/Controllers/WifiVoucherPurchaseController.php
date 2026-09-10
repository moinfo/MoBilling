<?php

namespace App\Http\Controllers;

use App\Http\Resources\WifiVoucherPurchaseResource;
use App\Jobs\Wifi\ProvisionWifiVoucherJob;
use App\Models\MikrotikRouter;
use App\Models\WifiPlan;
use App\Models\WifiVoucherPurchase;
use Illuminate\Http\Request;

class WifiVoucherPurchaseController extends Controller
{
    /**
     * Staff-recorded sale — cash or any other payment MoBilling didn't
     * itself collect (mirrors why: many walk-up customers only have cash
     * on hand, not mobile-money balance for the online Pesapal flow).
     * Marks the purchase completed immediately and reuses the exact same
     * provisioning/notification path as an online payment
     * (ProvisionWifiVoucherJob creates the hotspot user and texts/WhatsApps
     * the code to customer_phone) — nothing about delivery differs.
     */
    public function store(Request $request)
    {
        $data = $request->validate([
            'mikrotik_router_id' => 'required|uuid|exists:mikrotik_routers,id',
            'wifi_plan_id'       => 'required|uuid|exists:wifi_plans,id',
            'customer_phone'     => 'required|string|max:50',
            'customer_name'      => 'nullable|string|max:255',
            'payment_method'     => 'required|in:cash,mpesa,bank,other',
        ]);

        $router = MikrotikRouter::findOrFail($data['mikrotik_router_id']);
        $plan = WifiPlan::where('id', $data['wifi_plan_id'])
            ->where('mikrotik_router_id', $router->id)
            ->where('is_active', true)
            ->firstOrFail();

        $purchase = WifiVoucherPurchase::create([
            'mikrotik_router_id'  => $router->id,
            'wifi_plan_id'        => $plan->id,
            'customer_phone'      => $data['customer_phone'],
            'customer_name'       => $data['customer_name'] ?? null,
            'amount'              => $plan->price,
            'status'              => 'completed',
            'completed_at'        => now(),
            'payment_method_used' => $data['payment_method'],
        ]);

        ProvisionWifiVoucherJob::dispatch($purchase);

        return new WifiVoucherPurchaseResource($purchase->fresh()->load(['router:id,name', 'plan:id,name']));
    }

    public function index(Request $request)
    {
        $query = WifiVoucherPurchase::with(['router:id,name', 'plan:id,name']);

        if ($request->filled('mikrotik_router_id')) {
            $query->where('mikrotik_router_id', $request->mikrotik_router_id);
        }
        if ($request->filled('status')) {
            $query->where('status', $request->status);
        }
        if ($request->filled('search')) {
            $query->where('customer_phone', 'like', '%' . $request->search . '%');
        }

        return WifiVoucherPurchaseResource::collection(
            $query->orderByDesc('created_at')->paginate($request->per_page ?? 25)
        );
    }

    public function show(WifiVoucherPurchase $wifi_voucher_purchase)
    {
        return new WifiVoucherPurchaseResource($wifi_voucher_purchase->load(['router:id,name', 'plan:id,name']));
    }
}

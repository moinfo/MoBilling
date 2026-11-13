<?php

namespace App\Http\Controllers\Portal;

use App\Http\Controllers\Controller;
use App\Models\MikrotikRouter;
use App\Models\WifiPlan;
use App\Models\WifiVoucherPurchase;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * A client's own view of the WiFi hotspot routers a tenant has handed over
 * to them to self-manage (MikrotikRouter.client_id) — their routers, their
 * plans, their voucher sales. Staff still create/assign the router itself;
 * everything under it is the client's own from here on. Every method scopes
 * by $request->user()->client_id (same convention as PortalDashboardController)
 * since MikrotikRouter/WifiPlan/WifiVoucherPurchase only have BelongsToTenant,
 * not a client-level global scope.
 */
class PortalWifiController extends Controller
{
    private function myRouterIds(Request $request)
    {
        return MikrotikRouter::where('client_id', $request->user()->client_id)->pluck('id');
    }

    public function routers(Request $request)
    {
        $routers = MikrotikRouter::where('client_id', $request->user()->client_id)
            ->withCount('plans')
            ->orderBy('name')
            ->get(['id', 'name', 'host', 'payment_mode', 'is_active', 'last_tested_at', 'last_test_status']);

        return response()->json(['data' => $routers]);
    }

    public function plans(Request $request)
    {
        $plans = WifiPlan::whereIn('mikrotik_router_id', $this->myRouterIds($request))
            ->with('router:id,name')
            ->orderBy('price')
            ->get();

        return response()->json(['data' => $plans]);
    }

    public function storePlan(Request $request)
    {
        $myRouterIds = $this->myRouterIds($request);

        $data = $request->validate([
            'mikrotik_router_id' => ['required', 'uuid', Rule::in($myRouterIds->all())],
            'name'             => 'required|string|max:255',
            'duration_value'   => 'nullable|required_without:data_cap_mb|integer|min:1',
            'duration_unit'    => 'nullable|required_without:data_cap_mb|in:hours,days,weeks',
            'data_cap_mb'      => 'nullable|required_without:duration_value|integer|min:1',
            'speed_limit_mbps' => 'nullable|numeric|min:0.1|max:9999',
            'price'            => 'required|numeric|min:0',
            'hotspot_profile'  => 'nullable|string|max:255',
            'is_active'        => 'sometimes|boolean',
        ]);

        $plan = WifiPlan::create($data);
        return response()->json(['data' => $plan->load('router:id,name')], 201);
    }

    public function updatePlan(Request $request, WifiPlan $wifi_plan)
    {
        abort_unless($this->myRouterIds($request)->contains($wifi_plan->mikrotik_router_id), 404);

        $data = $request->validate([
            'name'             => 'sometimes|required|string|max:255',
            'duration_value'   => 'nullable|integer|min:1',
            'duration_unit'    => 'nullable|in:hours,days,weeks',
            'data_cap_mb'      => 'nullable|integer|min:1',
            'speed_limit_mbps' => 'nullable|numeric|min:0.1|max:9999',
            'price'            => 'sometimes|required|numeric|min:0',
            'hotspot_profile'  => 'nullable|string|max:255',
            'is_active'        => 'sometimes|boolean',
        ]);

        $wifi_plan->update($data);
        return response()->json(['data' => $wifi_plan->load('router:id,name')]);
    }

    public function destroyPlan(Request $request, WifiPlan $wifi_plan)
    {
        abort_unless($this->myRouterIds($request)->contains($wifi_plan->mikrotik_router_id), 404);

        $wifi_plan->delete();
        return response()->json(['message' => 'Plan deleted']);
    }

    /** Every sale on the client's own routers, whichever payment_mode — their full sales history. */
    public function vouchers(Request $request)
    {
        $query = WifiVoucherPurchase::whereIn('mikrotik_router_id', $this->myRouterIds($request))
            ->whereNotNull('completed_at')
            ->with(['router:id,name', 'plan:id,name']);

        $purchases = $query->orderByDesc('completed_at')->paginate($request->per_page ?? 25);

        $purchases->getCollection()->transform(fn ($p) => [
            'id'                => $p->id,
            'router'            => $p->router ? ['id' => $p->router->id, 'name' => $p->router->name] : null,
            'plan'              => $p->plan ? ['id' => $p->plan->id, 'name' => $p->plan->name] : null,
            'customer_phone'    => $p->customer_phone,
            'amount'            => $p->amount,
            'commission_amount' => $p->commission_amount,
            'net_amount'        => $p->net_amount,
            'completed_at'      => $p->completed_at,
            'settled_at'        => $p->settled_at,
        ]);

        return response()->json($purchases);
    }

    /**
     * Only meaningful for the client's platform_collected routers — a
     * self_managed router's sales land straight in the client's own Pesapal
     * account, so MoBilling owes them nothing back for those.
     */
    public function earningsSummary(Request $request)
    {
        $base = WifiVoucherPurchase::whereIn('mikrotik_router_id', $this->myRouterIds($request))
            ->whereHas('router', fn ($q) => $q->where('payment_mode', 'platform_collected'))
            ->whereNotNull('completed_at')
            ->whereNotNull('order_tracking_id');

        return response()->json(['data' => [
            'owed'            => round((float) (clone $base)->whereNull('settled_at')->sum('net_amount'), 2),
            'unsettled_count' => (clone $base)->whereNull('settled_at')->count(),
            'total_settled'   => round((float) (clone $base)->whereNotNull('settled_at')->sum('net_amount'), 2),
        ]]);
    }
}

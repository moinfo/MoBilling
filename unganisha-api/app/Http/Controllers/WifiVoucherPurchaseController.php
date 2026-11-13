<?php

namespace App\Http\Controllers;

use App\Http\Resources\WifiVoucherPurchaseResource;
use App\Jobs\Wifi\ProvisionWifiVoucherJob;
use App\Models\MikrotikRouter;
use App\Models\WifiPlan;
use App\Models\WifiVoucherPurchase;
use App\Notifications\WifiVoucherIssuedNotification;
use App\Services\Mikrotik\RouterOsService;
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

    /** Live data/time usage so far — queried straight from the router, on demand (staff asking "how much has this customer used?"). */
    public function usage(WifiVoucherPurchase $wifi_voucher_purchase)
    {
        if (!$wifi_voucher_purchase->hotspot_username) {
            return response()->json(['message' => 'This voucher has not been provisioned yet.'], 422);
        }

        return response()->json(['data' => $wifi_voucher_purchase->liveUsage()]);
    }

    /**
     * Immediately revokes a misbehaving customer's access: disables future
     * logins on the router AND kicks any session connected right now (see
     * RouterOsService::disableHotspotUser). The voucher itself isn't
     * deleted/refunded — this is a conduct action, not a payment reversal.
     */
    public function block(Request $request, WifiVoucherPurchase $wifi_voucher_purchase)
    {
        abort_unless($wifi_voucher_purchase->hotspot_username, 422, 'This voucher has not been provisioned yet.');
        abort_if($wifi_voucher_purchase->blocked_at, 422, 'This voucher is already blocked.');

        $data = $request->validate(['reason' => 'nullable|string|max:500']);

        $router = $wifi_voucher_purchase->router;
        abort_unless($router, 404, 'Router not found.');

        try {
            (new RouterOsService($router))->disableHotspotUser($wifi_voucher_purchase->hotspot_username);
        } catch (\Throwable $e) {
            return response()->json(['message' => 'Could not reach the router to block this voucher: ' . $e->getMessage()], 502);
        }

        $wifi_voucher_purchase->update([
            'blocked_at'     => now(),
            'blocked_reason' => $data['reason'] ?? null,
            'blocked_by'     => auth()->id(),
        ]);

        return new WifiVoucherPurchaseResource($wifi_voucher_purchase->fresh()->load(['router:id,name', 'plan:id,name']));
    }

    /**
     * The exact SMS/WhatsApp text the customer would get — lets staff
     * manually relay it (phone call, their own WhatsApp, etc.) when the
     * tenant has no SMS/WhatsApp sending configured, without duplicating
     * WifiVoucherIssuedNotification's message-formatting logic.
     */
    public function message(WifiVoucherPurchase $wifi_voucher_purchase)
    {
        abort_unless($wifi_voucher_purchase->hotspot_username, 422, 'This voucher has not been provisioned yet.');

        $notification = new WifiVoucherIssuedNotification($wifi_voucher_purchase);

        return response()->json(['data' => ['message' => $notification->toSms($wifi_voucher_purchase)]]);
    }

    /**
     * Re-sends the voucher notification on demand — e.g. the tenant just
     * turned SMS/WhatsApp on after the original send had nothing to go
     * through (see WifiVoucherIssuedNotification::via()), or a transient
     * send failure needs retrying.
     */
    public function resend(WifiVoucherPurchase $wifi_voucher_purchase)
    {
        abort_unless($wifi_voucher_purchase->hotspot_username, 422, 'This voucher has not been provisioned yet.');

        $tenant = $wifi_voucher_purchase->tenant()->withoutGlobalScopes()->first();
        if (!$tenant?->sms_enabled && !$tenant?->whatsapp_enabled) {
            return response()->json([
                'message' => 'SMS and WhatsApp are not enabled for this tenant, so there is nothing to resend through — enable one in Settings, or use "View message" to relay the code yourself.',
            ], 422);
        }

        try {
            $wifi_voucher_purchase->notify(new WifiVoucherIssuedNotification($wifi_voucher_purchase));
        } catch (\Throwable $e) {
            return response()->json(['message' => 'Could not resend: ' . $e->getMessage()], 502);
        }

        return response()->json(['message' => 'Voucher resent to the customer.']);
    }

    public function unblock(WifiVoucherPurchase $wifi_voucher_purchase)
    {
        abort_unless($wifi_voucher_purchase->blocked_at, 422, 'This voucher is not blocked.');

        $router = $wifi_voucher_purchase->router;
        abort_unless($router, 404, 'Router not found.');

        try {
            (new RouterOsService($router))->enableHotspotUser($wifi_voucher_purchase->hotspot_username);
        } catch (\Throwable $e) {
            return response()->json(['message' => 'Could not reach the router to unblock this voucher: ' . $e->getMessage()], 502);
        }

        $wifi_voucher_purchase->update(['blocked_at' => null, 'blocked_reason' => null, 'blocked_by' => null]);

        return new WifiVoucherPurchaseResource($wifi_voucher_purchase->fresh()->load(['router:id,name', 'plan:id,name']));
    }
}

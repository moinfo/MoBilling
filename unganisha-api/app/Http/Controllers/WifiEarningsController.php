<?php

namespace App\Http\Controllers;

use App\Models\User;
use App\Models\WifiVoucherPurchase;
use App\Notifications\WifiPayoutRequestedNotification;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Notification;

/**
 * Tenant-facing view of what MoBilling owes them for platform_collected
 * WiFi voucher sales (MoBilling's own Pesapal account did the collecting —
 * see PesapalWebhookController::processWifiVoucherCompleted()). Mirrors
 * Admin\WifiSettlementController's query shape, but auto-scoped to the
 * caller's own tenant via the normal BelongsToTenant global scope (no
 * withoutGlobalScopes() — this is the opposite audience: the tenant
 * checking their own balance, not a superadmin auditing everyone).
 */
class WifiEarningsController extends Controller
{
    private function baseQuery()
    {
        return WifiVoucherPurchase::whereHas('router', fn ($q) => $q->where('payment_mode', 'platform_collected'))
            ->whereNotNull('completed_at')
            // Excludes manual/cash sales (WifiVoucherPurchaseController::store()):
            // those never set order_tracking_id since no Pesapal order was
            // ever placed, so MoBilling collected nothing for them —
            // there's nothing owed back to the tenant.
            ->whereNotNull('order_tracking_id');
    }

    public function summary()
    {
        return response()->json(['data' => [
            'owed'            => round((float) (clone $this->baseQuery())->whereNull('settled_at')->sum('net_amount'), 2),
            'unsettled_count' => (clone $this->baseQuery())->whereNull('settled_at')->count(),
            'total_settled'   => round((float) (clone $this->baseQuery())->whereNotNull('settled_at')->sum('net_amount'), 2),
        ]]);
    }

    public function index(Request $request)
    {
        $query = $this->baseQuery()->with(['router:id,name', 'plan:id,name']);

        if ($request->filled('settled')) {
            $request->boolean('settled') ? $query->whereNotNull('settled_at') : $query->whereNull('settled_at');
        }

        $purchases = $query->orderByDesc('completed_at')->paginate($request->per_page ?? 25);

        $purchases->getCollection()->transform(fn ($p) => [
            'id'                   => $p->id,
            'router'               => $p->router ? ['id' => $p->router->id, 'name' => $p->router->name] : null,
            'plan'                 => $p->plan ? ['id' => $p->plan->id, 'name' => $p->plan->name] : null,
            'customer_phone'       => $p->customer_phone,
            'amount'               => $p->amount,
            'commission_amount'    => $p->commission_amount,
            'net_amount'           => $p->net_amount,
            'completed_at'         => $p->completed_at,
            'settled_at'           => $p->settled_at,
            'settlement_method'    => $p->settlement_method,
            'settlement_reference' => $p->settlement_reference,
        ]);

        return response()->json($purchases);
    }

    /**
     * No automated disbursement API exists (same constraint documented on
     * Admin\WifiSettlementController) — this can't move money itself. It
     * just pings MoInfoTech's superadmins that a tenant wants to be paid
     * now, instead of the tenant having to message support directly.
     */
    public function requestPayout()
    {
        $owed = (clone $this->baseQuery())->whereNull('settled_at')->sum('net_amount');
        abort_if($owed <= 0, 422, 'You have nothing owed to withdraw right now.');

        $tenant = auth()->user()->tenant;
        $superAdmins = User::where('role', 'super_admin')->get();

        Notification::send($superAdmins, new WifiPayoutRequestedNotification($tenant, round((float) $owed, 2), auth()->user()));

        return response()->json(['message' => 'Payout request sent — MoInfoTech will process it shortly.']);
    }
}

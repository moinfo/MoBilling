<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Tenant;
use App\Models\WifiVoucherPurchase;
use Illuminate\Http\Request;

/**
 * Cross-tenant settlement ledger for platform_collected WiFi vouchers —
 * MoBilling's own Pesapal account collected the money (see
 * PesapalWebhookController::processWifiVoucherCompleted()); this is where
 * a superadmin tracks what's owed to each tenant and records that it was
 * paid out by hand. Mirrors RefundController's non-wallet refunds: an
 * audit record, not a real money transfer — no disbursement API exists.
 */
class WifiSettlementController extends Controller
{
    private function authorize(): void
    {
        if (!auth()->user()->isSuperAdmin()) {
            abort(403, 'Unauthorized');
        }
    }

    /**
     * `status` is overloaded: ProvisionWifiVoucherJob flips it to `failed`
     * if the router happens to be unreachable, even though payment
     * genuinely succeeded — the customer's money already landed in
     * MoBilling's Pesapal account and the tenant is still owed their
     * share regardless of a router hiccup. `completed_at` is only ever
     * set once, inside processWifiVoucherCompleted(), and the
     * provisioning job never touches it — so it's the reliable "payment
     * succeeded" signal for settlement purposes, not `status`.
     */
    private function baseQuery()
    {
        return WifiVoucherPurchase::withoutGlobalScopes()
            ->whereHas('router', fn ($q) => $q->where('payment_mode', 'platform_collected'))
            ->whereNotNull('completed_at');
    }

    public function index(Request $request)
    {
        $this->authorize();

        $query = $this->baseQuery()->with(['router:id,name', 'plan:id,name']);

        if ($request->filled('tenant_id')) {
            $query->where('tenant_id', $request->tenant_id);
        }
        if ($request->filled('settled')) {
            $request->boolean('settled') ? $query->whereNotNull('settled_at') : $query->whereNull('settled_at');
        }

        $purchases = $query->orderByDesc('completed_at')->paginate($request->per_page ?? 25);

        $tenantIds = collect($purchases->items())->pluck('tenant_id')->unique();
        $tenants = Tenant::withoutGlobalScopes()->whereIn('id', $tenantIds)->pluck('name', 'id');

        $purchases->getCollection()->transform(fn ($p) => [
            'id'                   => $p->id,
            'tenant_id'            => $p->tenant_id,
            'tenant_name'          => $tenants[$p->tenant_id] ?? 'Unknown',
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
            'settlement_notes'     => $p->settlement_notes,
        ]);

        return response()->json($purchases);
    }

    /** Total owed (unsettled net_amount) per tenant. */
    public function summary()
    {
        $this->authorize();

        $rows = $this->baseQuery()
            ->whereNull('settled_at')
            ->selectRaw('tenant_id, COUNT(*) as count, SUM(net_amount) as total_owed')
            ->groupBy('tenant_id')
            ->having('total_owed', '>', 0)
            ->get();

        $tenants = Tenant::withoutGlobalScopes()->whereIn('id', $rows->pluck('tenant_id'))->pluck('name', 'id');

        return response()->json(['data' => $rows->map(fn ($r) => [
            'tenant_id'   => $r->tenant_id,
            'tenant_name' => $tenants[$r->tenant_id] ?? 'Unknown',
            'count'       => (int) $r->count,
            'total_owed'  => round((float) $r->total_owed, 2),
        ])->values()]);
    }

    /**
     * Manual lookup, not implicit route-model binding: WifiVoucherPurchase
     * is BelongsToTenant-scoped, and implicit binding would apply that
     * global scope against auth()->user()->tenant_id — for a superadmin
     * (no meaningful tenant_id of their own) that would 404 every purchase
     * belonging to any actual tenant.
     */
    public function settle(Request $request, string $id)
    {
        $this->authorize();

        $wifi_voucher_purchase = WifiVoucherPurchase::withoutGlobalScopes()->findOrFail($id);

        abort_unless($wifi_voucher_purchase->completed_at !== null, 422, 'This purchase has not been paid yet.');
        abort_if($wifi_voucher_purchase->settled_at, 422, 'This purchase has already been settled.');

        $data = $request->validate([
            'method'    => 'required|in:cash,bank,mpesa,pesapal,other',
            'reference' => 'nullable|string|max:255',
            'notes'     => 'nullable|string|max:1000',
        ]);

        $wifi_voucher_purchase->update([
            'settled_at'            => now(),
            'settlement_method'     => $data['method'],
            'settlement_reference'  => $data['reference'] ?? null,
            'settlement_notes'      => $data['notes'] ?? null,
            'settled_by'            => auth()->id(),
        ]);

        return response()->json([
            'message' => 'Marked as settled.',
            'data'    => $wifi_voucher_purchase->fresh(),
        ]);
    }
}

<?php

namespace App\Http\Controllers\Public;

use App\Http\Controllers\Controller;
use App\Models\MikrotikRouter;
use App\Models\WifiVoucherPurchase;
use App\Services\Mikrotik\RouterOsService;
use App\Services\PesapalService;
use App\Services\TenantPesapalService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

/**
 * Public, unauthenticated WiFi voucher checkout — the buyer is a walk-in
 * customer with no MoBilling account, identified only by phone. Mirrors
 * LicensePurchaseController's shape: this only ever registers the order
 * with the router-owning tenant's own Pesapal account and hands back
 * where to send the browser to pay. Completion (provisioning the hotspot
 * user) happens entirely in TenantPesapalWebhookController's IPN handler.
 */
class WifiCheckoutController extends Controller
{
    public function show(MikrotikRouter $router)
    {
        abort_unless($router->is_active, 404);

        $router->loadMissing(['tenant' => fn ($q) => $q->withoutGlobalScopes()]);

        return response()->json(['data' => [
            'router' => [
                'id'   => $router->id,
                'name' => $router->name,
            ],
            'tenant' => [
                'name'      => $router->tenant?->name,
                'logo_url'  => $router->tenant?->logo_url,
                'currency'  => $router->tenant?->currency ?? 'TZS',
            ],
            'plans' => $router->plans()->where('is_active', true)->orderBy('price')->get()
                ->map(fn ($p) => [
                    'id'             => $p->id,
                    'name'           => $p->name,
                    'duration_value' => $p->duration_value,
                    'duration_unit'  => $p->duration_unit,
                    'data_cap_mb'    => $p->data_cap_mb,
                    'price'          => (float) $p->price,
                ]),
        ]]);
    }

    public function checkout(Request $request, MikrotikRouter $router)
    {
        abort_unless($router->is_active, 404);

        $data = $request->validate([
            'phone'        => 'required|string|max:50',
            'name'         => 'nullable|string|max:255',
            'wifi_plan_id' => 'required|uuid',
        ]);

        $plan = $router->plans()->where('id', $data['wifi_plan_id'])->where('is_active', true)->first();
        if (!$plan) {
            return response()->json(['message' => 'This plan is not currently available.'], 422);
        }

        $router->loadMissing(['tenant' => fn ($q) => $q->withoutGlobalScopes()]);
        $tenant = $router->tenant;
        $platformCollected = $router->payment_mode === 'platform_collected';

        if (!$tenant || (!$platformCollected && !$tenant->pesapal_consumer_key)) {
            return response()->json(['message' => 'This hotspot is not accepting payments right now — please try again later.'], 422);
        }

        $purchase = WifiVoucherPurchase::create([
            'tenant_id'          => $tenant->id,
            'mikrotik_router_id' => $router->id,
            'wifi_plan_id'       => $plan->id,
            'customer_phone'     => $data['phone'],
            'customer_name'      => $data['name'] ?? null,
            'amount'             => $plan->price,
            'status'             => 'pending',
        ]);

        try {
            // platform_collected: MoBilling's own Pesapal account collects
            // the money; the tenant is settled manually later (see
            // Admin\WifiSettlementController). self_managed: unchanged —
            // the tenant's own Pesapal account collects it directly.
            $pesapal = $platformCollected ? new PesapalService() : new TenantPesapalService($tenant);
            $result = $pesapal->submitOrder(
                'WIFI-' . Str::upper(Str::random(8)),
                (float) $plan->price,
                "WiFi voucher — {$plan->name}",
                ['phone' => $data['phone'], 'first_name' => $data['name'] ?? 'Guest'],
                config('app.url') . "/wifi/{$router->id}/status/{$purchase->id}",
            );
        } catch (\Throwable $e) {
            Log::error('WiFi voucher checkout: Pesapal order submission failed', [
                'purchase_id' => $purchase->id,
                'error'       => $e->getMessage(),
            ]);

            return response()->json(['message' => 'Could not start payment. Please try again shortly.'], 500);
        }

        $purchase->update([
            'order_tracking_id'    => $result['order_tracking_id'] ?? null,
            'pesapal_redirect_url' => $result['redirect_url'] ?? null,
        ]);

        return response()->json(['data' => [
            'purchase_id'  => $purchase->id,
            'redirect_url' => $result['redirect_url'] ?? null,
        ]], 201);
    }

    public function status(WifiVoucherPurchase $purchase)
    {
        $purchase->loadMissing(['router', 'plan']);
        $completed = $purchase->status === 'completed';

        return response()->json(['data' => [
            'id'               => $purchase->id,
            'status'           => $purchase->status,
            'hotspot_username' => $completed ? $purchase->hotspot_username : null,
            'hotspot_password' => $completed ? $purchase->hotspot_password : null,
            // No fixed expiry date up front — RouterOS's own time limit
            // only starts counting from first login, so there's nothing
            // truthful to quote yet. Describes the plan's limit(s) instead;
            // see balance() for live remaining-time/data once they've
            // started using it.
            'plan' => $completed ? [
                'duration_value' => $purchase->plan?->duration_value,
                'duration_unit'  => $purchase->plan?->duration_unit,
                'data_cap_mb'    => $purchase->plan?->data_cap_mb,
            ] : null,
            // Lets the browser auto-login by navigating straight to the
            // router's own hotspot login endpoint — only present when the
            // router owner has configured its LAN-side address.
            'local_login_host' => $completed ? $purchase->router?->local_login_host : null,
        ]]);
    }

    /**
     * Lets a customer check their remaining data/time from anywhere —
     * doesn't require being connected to the hotspot. Both figures are
     * live: data usage only exists on the router, and time remaining
     * means "connected-time budget left" (limit-uptime), which only the
     * router can answer — MoBilling doesn't store a wall-clock deadline
     * (see ProvisionWifiVoucherJob).
     */
    public function balance(Request $request, MikrotikRouter $router)
    {
        $data = $request->validate(['code' => 'required|string|max:50']);

        $purchase = WifiVoucherPurchase::where('mikrotik_router_id', $router->id)
            ->where('hotspot_username', strtoupper(trim($data['code'])))
            ->where('status', 'completed')
            ->with('plan')
            ->latest()
            ->first();

        if (!$purchase) {
            return response()->json(['message' => 'Voucher not found. Check the code and try again.'], 404);
        }

        $usage = null;
        try {
            $usage = (new RouterOsService($router))->getHotspotUserUsage($purchase->hotspot_username);
        } catch (\Throwable $e) {
            Log::warning('WiFi balance check: router query failed', [
                'purchase_id' => $purchase->id,
                'error'       => $e->getMessage(),
            ]);
        }

        $usedBytes = $usage ? $usage['bytes_in'] + $usage['bytes_out'] : null;
        $dataCapMb = $purchase->plan?->data_cap_mb;
        $durationSeconds = $purchase->plan?->durationSeconds();
        $usedSeconds = $usage['uptime_seconds'] ?? null;

        return response()->json(['data' => [
            'hotspot_username'      => $purchase->hotspot_username,
            'data_cap_mb'           => $dataCapMb,
            'data_used_mb'          => $usedBytes !== null ? round($usedBytes / 1048576, 1) : null,
            'data_remaining_mb'     => ($dataCapMb && $usedBytes !== null)
                ? max(0, round($dataCapMb - $usedBytes / 1048576, 1))
                : null,
            'duration_seconds'      => $durationSeconds,
            'time_used_seconds'     => $usedSeconds,
            'time_remaining_seconds' => ($durationSeconds !== null && $usedSeconds !== null)
                ? max(0, $durationSeconds - $usedSeconds)
                : null,
            'router_reachable' => $usage !== null,
        ]]);
    }
}

<?php

namespace App\Http\Controllers\Public;

use App\Http\Controllers\Controller;
use App\Models\MikrotikRouter;
use App\Models\WifiVoucherPurchase;
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
        if (!$tenant || !$tenant->pesapal_consumer_key) {
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
            $pesapal = new TenantPesapalService($tenant);
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
        return response()->json(['data' => [
            'id'                 => $purchase->id,
            'status'             => $purchase->status,
            'hotspot_username'   => $purchase->status === 'completed' ? $purchase->hotspot_username : null,
            'hotspot_password'   => $purchase->status === 'completed' ? $purchase->hotspot_password : null,
            'voucher_expires_at' => $purchase->voucher_expires_at?->toISOString(),
        ]]);
    }
}

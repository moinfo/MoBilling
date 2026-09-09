<?php

namespace App\Jobs\Wifi;

use App\Models\WifiVoucherPurchase;
use App\Notifications\WifiVoucherIssuedNotification;
use App\Services\Mikrotik\RouterOsService;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

class ProvisionWifiVoucherJob extends BaseWifiJob
{
    public function __construct(public WifiVoucherPurchase $purchase) {}

    public function handle(): void
    {
        $purchase = $this->purchase->fresh(['router', 'plan']);
        if (!$purchase || $purchase->status !== 'completed' || $purchase->hotspot_username) {
            return; // not paid, or already provisioned (idempotent)
        }

        $router = $purchase->router;
        $plan = $purchase->plan;
        if (!$router || !$plan) {
            Log::warning("ProvisionWifiVoucherJob: purchase {$purchase->id} missing router/plan — skipped");
            return;
        }

        // One code for both username and password — a single scratch-card
        // style code is faster to type on a phone hotspot login page than
        // two separate values.
        $code = strtoupper(Str::random(8));

        $this->guard($purchase, function () use ($purchase, $router, $plan, $code) {
            (new RouterOsService($router))->createHotspotUser(
                $code, $code, $plan->hotspot_profile, $plan->durationSeconds()
            );

            $purchase->update([
                'hotspot_username'   => $code,
                'hotspot_password'   => $code,
                'voucher_expires_at' => now()->addSeconds($plan->durationSeconds()),
            ]);

            try {
                $purchase->notify(new WifiVoucherIssuedNotification($purchase));
            } catch (\Throwable $e) {
                Log::warning("WiFi voucher notification failed for {$purchase->id}: {$e->getMessage()}");
            }
        });
    }
}

<?php

namespace App\Jobs\Wifi;

use App\Models\WifiVoucherPurchase;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\Log;

/**
 * Mirrors App\Jobs\Hosting\BaseHostingJob — provisioning jobs never throw
 * out of handle(): with the sync queue driver they run inline inside the
 * Pesapal IPN request, and a router outage must not break that webhook
 * response. Failures set the purchase to `failed` and are visible to
 * staff; router calls are safely retryable (no real-world money spent
 * per-call, unlike a registry operation), hence tries=3 with backoff.
 */
abstract class BaseWifiJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public int $tries = 3;

    public function backoff(): array
    {
        return [60, 300, 900];
    }

    protected function guard(WifiVoucherPurchase $purchase, \Closure $fn): void
    {
        try {
            $fn();
        } catch (\Throwable $e) {
            $purchase->update(['status' => 'failed']);
            Log::error(static::class . " failed for wifi voucher purchase {$purchase->id}", [
                'error' => $e->getMessage(),
            ]);
        }
    }
}

<?php

namespace App\Services\Hosting;

use App\Jobs\Hosting\ChangeHostingPackage;
use App\Models\ClientSubscription;
use App\Models\ProductService;

/**
 * Hosting plan upgrade/downgrade (docs: WHMCS-parity, no full proration engine).
 * Upgrades bill the prorated price difference for the remaining period;
 * downgrades are free and immediate (no credit for the unused difference).
 */
class PlanChangeService
{
    private const CYCLE_DAYS = [
        'monthly' => 30, 'quarterly' => 91, 'half_yearly' => 182, 'yearly' => 365,
    ];

    /** Prorated amount due now for switching to $new (0 for downgrades). */
    public function proratedCharge(ClientSubscription $sub, ProductService $new): float
    {
        $current = $sub->productService;
        $diff = (float) $new->price - (float) ($current?->price ?? 0);
        if ($diff <= 0) {
            return 0.0;
        }

        $cycleDays = self::CYCLE_DAYS[$current?->billing_cycle ?? 'yearly'] ?? 365;
        $remaining = $sub->expire_date
            ? max(0, now()->startOfDay()->diffInDays($sub->expire_date, false))
            : $cycleDays;
        $remaining = min($remaining, $cycleDays);

        return round($diff * $remaining / $cycleDays, 2);
    }

    /**
     * Switch the subscription to the new plan and change the cPanel package.
     * The recurring amount is re-derived from the new product (WHMCS updates
     * the recurring on a plan change), so any manual override is cleared.
     */
    public function apply(ClientSubscription $sub, ProductService $new): void
    {
        $meta = $sub->metadata ?? [];
        unset($meta['pending_plan_change']);
        $meta['plan_changed_at'] = now()->toIso8601String();

        $sub->update([
            'product_service_id' => $new->id,
            'recurring_amount'   => null, // re-derive from the new product's price
            'metadata'           => $meta,
        ]);

        $account = $sub->hostingAccount;
        if ($account && $new->cpanel_package && $account->package !== $new->cpanel_package) {
            ChangeHostingPackage::dispatch($account, $new->cpanel_package);
        }
    }
}

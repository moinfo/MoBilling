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

    /** upgrade | downgrade | same, by product price. */
    public function direction(ClientSubscription $sub, ProductService $new): string
    {
        $diff = (float) $new->price - (float) ($sub->productService?->price ?? 0);
        return $diff > 0 ? 'upgrade' : ($diff < 0 ? 'downgrade' : 'same');
    }

    /**
     * Prorated amount due now for switching to $new (0 for downgrades/same).
     * The per-cycle price difference is scaled by the remaining term and by
     * quantity (recurring bills price × qty). If the term has already lapsed
     * (expired / due today), an upgrade is charged the FULL one-cycle
     * difference — never free — since it starts a fresh term on the new plan.
     */
    public function proratedCharge(ClientSubscription $sub, ProductService $new): float
    {
        $current = $sub->productService;
        $diff = (float) $new->price - (float) ($current?->price ?? 0);
        if ($diff <= 0) {
            return 0.0; // downgrade / same → no charge (WHMCS default: no credit)
        }

        $qty = max(1, (int) $sub->quantity);
        $cycleDays = self::CYCLE_DAYS[$current?->billing_cycle ?? 'yearly'] ?? 365;
        $remaining = $sub->expire_date
            ? (int) now()->startOfDay()->diffInDays($sub->expire_date, false)
            : $cycleDays;
        $remaining = min($remaining, $cycleDays);

        // Lapsed/at-due upgrade → full cycle difference, not free.
        $factor = $remaining > 0 ? $remaining / $cycleDays : 1.0;

        return round($diff * $qty * $factor, 2);
    }

    /**
     * Prorated credit due to the client for a downgrade (0 for upgrades/same,
     * and 0 when the term has lapsed — no unused time to refund). Mirrors the
     * upgrade proration on the negative price difference × quantity.
     */
    public function proratedCredit(ClientSubscription $sub, ProductService $new): float
    {
        $current = $sub->productService;
        $diff = (float) ($current?->price ?? 0) - (float) $new->price;
        if ($diff <= 0) {
            return 0.0; // upgrade / same
        }

        $qty = max(1, (int) $sub->quantity);
        $cycleDays = self::CYCLE_DAYS[$current?->billing_cycle ?? 'yearly'] ?? 365;
        $remaining = $sub->expire_date
            ? (int) now()->startOfDay()->diffInDays($sub->expire_date, false)
            : $cycleDays;
        $remaining = min(max(0, $remaining), $cycleDays);
        if ($remaining <= 0) {
            return 0.0; // term already lapsed → nothing to refund
        }

        return round($diff * $qty * $remaining / $cycleDays, 2);
    }

    /**
     * Switch the subscription to the new plan and change the cPanel package.
     * The recurring amount is re-derived from the new product (WHMCS updates
     * the recurring on a plan change), so any manual override is cleared.
     */
    public function apply(ClientSubscription $sub, ProductService $new): void
    {
        // Credit the unused difference on a downgrade BEFORE switching product
        // (proratedCredit reads the current product price).
        $credit = config('whmcs.credit_on_downgrade') ? $this->proratedCredit($sub, $new) : 0.0;

        $meta = $sub->metadata ?? [];
        unset($meta['pending_plan_change']);
        $meta['plan_changed_at'] = now()->toIso8601String();

        $oldName = $sub->productService?->name;

        $sub->update([
            'product_service_id' => $new->id,
            'recurring_amount'   => null, // re-derive from the new product's price
            'metadata'           => $meta,
        ]);

        if ($credit > 0 && $sub->client_id) {
            try {
                $client = \App\Models\Client::withoutGlobalScopes()->find($sub->client_id);
                if ($client) {
                    app(\App\Services\CreditService::class)->adjust(
                        $client, $credit, 'adjustment',
                        "Downgrade credit: {$oldName} → {$new->name} (unused term)",
                        null, auth()->id()
                    );
                }
            } catch (\Throwable $e) {
                \Illuminate\Support\Facades\Log::warning("Downgrade credit failed for sub {$sub->id}: {$e->getMessage()}");
            }
        }

        $account = $sub->hostingAccount;
        if (!$account) {
            return;
        }
        if ($new->provisioning_type === 'whm_cpanel' && $new->cpanel_package && $account->package !== $new->cpanel_package) {
            ChangeHostingPackage::dispatch($account, $new->cpanel_package);
        } else {
            // Billing plan changed but the server package did not — surface it.
            \Illuminate\Support\Facades\Log::info(
                "PlanChange: {$sub->id} switched to {$new->name} without a cPanel package change" .
                ($new->cpanel_package ? '' : ' (product has no cpanel_package)')
            );
        }
    }
}

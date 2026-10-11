<?php

namespace App\Observers;

use App\Jobs\Hosting\ProvisionHostingAccount;
use App\Jobs\Hosting\ReactivateHostingAccount;
use App\Jobs\Hosting\SuspendHostingAccount;
use App\Jobs\Linode\ProvisionLinodeVpsInstance;
use App\Jobs\Linode\ReactivateLinodeVpsInstance;
use App\Jobs\Linode\SuspendLinodeVpsInstance;
use App\Models\ClientSubscription;

/**
 * Single hook point mapping subscription status transitions to hosting jobs
 * (docs/IMPLEMENTATION_PLAN.md §A3). Note design decision Q3: cancellation
 * SUSPENDS the account; termination is a manual, permission-gated admin action.
 */
class ClientSubscriptionObserver
{
    public function updated(ClientSubscription $sub): void
    {
        if (!$sub->wasChanged('status')) {
            return;
        }

        $product = $sub->productService;

        // Linode Server products are MANUAL, billing-only: a status change only changes
        // billing state. We deliberately do NOT touch the Linode server (no shutdown/
        // delete/API call of any kind); staff are alerted via the Linode audit log + app log.
        if ($product && $product->provisioning_type === 'linode') {
            app(\App\Services\Linode\LinodeBilling::class)->noteStatusChange($sub);
            return;
        }

        // Linode VPS products auto-provision a real, billable VPS — same
        // wallet gate and active/suspended/cancelled mapping as WHM hosting
        // below, just against a LinodeResource instead of a HostingAccount.
        if ($product && $product->provisioning_type === 'linode_vps') {
            $resource = $sub->linodeResource;

            match ($sub->status) {
                'active'    => $resource
                                ? ReactivateLinodeVpsInstance::dispatch($resource)
                                : (app(\App\Services\TenantWalletGateService::class)->allowHostingProvision($sub) ? ProvisionLinodeVpsInstance::dispatch($sub) : null),
                'suspended' => $resource ? SuspendLinodeVpsInstance::dispatch($resource, 'Unpaid invoice') : null,
                'cancelled' => $resource ? SuspendLinodeVpsInstance::dispatch($resource, 'Subscription cancelled') : null,
                default     => null,
            };
            return;
        }

        if (!$product || $product->provisioning_type !== 'whm_cpanel') {
            return;
        }

        $account = $sub->hostingAccount;

        match ($sub->status) {
            // White-label reseller tenants (Tenant::is_wallet_gated) only: a fresh
            // provision must be paid for at cost from the tenant's wallet first —
            // see TenantWalletGateService. Every other tenant's allowHostingProvision()
            // returns true immediately, so this changes nothing for them.
            'active'    => $account
                            ? ReactivateHostingAccount::dispatch($account)
                            : (($product->auto_provision && app(\App\Services\TenantWalletGateService::class)->allowHostingProvision($sub)) ? ProvisionHostingAccount::dispatch($sub) : null),
            'suspended' => $account ? SuspendHostingAccount::dispatch($account, 'Unpaid invoice') : null,
            'cancelled' => $account ? SuspendHostingAccount::dispatch($account, 'Subscription cancelled') : null,
            default     => null,
        };
    }
}

<?php

namespace App\Observers;

use App\Jobs\Hosting\ProvisionHostingAccount;
use App\Jobs\Hosting\ReactivateHostingAccount;
use App\Jobs\Hosting\SuspendHostingAccount;
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
        if (!$product || $product->provisioning_type !== 'whm_cpanel') {
            return;
        }

        $account = $sub->hostingAccount;

        match ($sub->status) {
            'active'    => $account
                            ? ReactivateHostingAccount::dispatch($account)
                            : ($product->auto_provision ? ProvisionHostingAccount::dispatch($sub) : null),
            'suspended' => $account ? SuspendHostingAccount::dispatch($account, 'Unpaid invoice') : null,
            'cancelled' => $account ? SuspendHostingAccount::dispatch($account, 'Subscription cancelled') : null,
            default     => null,
        };
    }
}

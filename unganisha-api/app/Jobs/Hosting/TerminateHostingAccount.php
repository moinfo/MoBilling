<?php

namespace App\Jobs\Hosting;

use App\Models\HostingAccount;

/**
 * Destructive — deletes the cPanel account and its data. Only dispatched from the
 * explicit admin action (hosting.terminate permission), never automatically
 * (design decision Q3: cancellations auto-SUSPEND; termination stays manual).
 */
class TerminateHostingAccount extends BaseHostingJob
{
    public function __construct(public HostingAccount $account) {}

    public function handle(): void
    {
        $account = $this->account->fresh('server');
        if (!$account || $account->status === 'terminated') return;

        $this->guard($account, function () use ($account) {
            $this->whm($account)->terminate($account->cpanel_username);
            $account->update(['status' => 'terminated']);
        });
    }
}

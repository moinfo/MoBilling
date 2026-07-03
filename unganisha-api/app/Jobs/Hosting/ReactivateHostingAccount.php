<?php

namespace App\Jobs\Hosting;

use App\Models\HostingAccount;

class ReactivateHostingAccount extends BaseHostingJob
{
    public function __construct(public HostingAccount $account) {}

    public function handle(): void
    {
        $account = $this->account->fresh('server');
        if (!$account || !in_array($account->status, ['suspended', 'failed'])) return;

        $this->guard($account, function () use ($account) {
            $this->whm($account)->unsuspend($account->cpanel_username);
            $account->update(['status' => 'active']);
        });
    }
}

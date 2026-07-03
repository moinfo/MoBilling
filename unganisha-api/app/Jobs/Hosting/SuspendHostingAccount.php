<?php

namespace App\Jobs\Hosting;

use App\Models\HostingAccount;

class SuspendHostingAccount extends BaseHostingJob
{
    public function __construct(public HostingAccount $account, public string $reason = 'Unpaid invoice') {}

    public function handle(): void
    {
        $account = $this->account->fresh('server');
        if (!$account || !in_array($account->status, ['active', 'failed'])) return;

        $this->guard($account, function () use ($account) {
            $this->whm($account)->suspend($account->cpanel_username, $this->reason);
            $account->update(['status' => 'suspended']);
        });
    }
}

<?php

namespace App\Jobs\Hosting;

use App\Models\HostingAccount;

class ChangeHostingPackage extends BaseHostingJob
{
    public function __construct(public HostingAccount $account, public string $package) {}

    public function handle(): void
    {
        $account = $this->account->fresh('server');
        if (!$account) return;

        $this->guard($account, function () use ($account) {
            $this->whm($account)->changePackage($account->cpanel_username, $this->package);
            $account->update(['package' => $this->package]);
        });
    }
}

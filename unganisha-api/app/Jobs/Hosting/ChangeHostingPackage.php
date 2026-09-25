<?php

namespace App\Jobs\Hosting;

use App\Models\HostingAccount;
use App\Services\Hosting\BandwidthSuspensionService;

class ChangeHostingPackage extends BaseHostingJob
{
    public function __construct(public HostingAccount $account, public string $package, public ?int $newLimitBytes = null) {}

    public function handle(): void
    {
        $account = $this->account->fresh('server');
        if (!$account) return;

        // Decided BEFORE the switch: a bandwidth-suspended account that upgrades is restored below.
        $wasBandwidthSuspended = app(BandwidthSuspensionService::class)->isBandwidthSuspended($account);

        $this->guard($account, function () use ($account) {
            $this->whm($account)->changePackage($account->cpanel_username, $this->package);
            $account->update(['package' => $this->package]);
        });

        if ($wasBandwidthSuspended && $account->fresh()->status === 'suspended') {
            app(BandwidthSuspensionService::class)->afterPackageChange($account, $this->newLimitBytes);
        }
    }
}

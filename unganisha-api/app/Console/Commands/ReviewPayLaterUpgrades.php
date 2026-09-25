<?php

namespace App\Console\Commands;

use App\Services\Hosting\PayLaterUpgradeService;
use Illuminate\Console\Command;

class ReviewPayLaterUpgrades extends Command
{
    protected $signature = 'hosting:review-pay-later-upgrades {--dry-run : Report what would be sent, change nothing}';

    protected $description = 'Remind clients about unpaid "upgrade now, pay later" invoices and alert staff when they stay unpaid (never reverts or suspends anything)';

    public function handle(PayLaterUpgradeService $service): int
    {
        $dry = (bool) $this->option('dry-run');
        $r = $service->review($dry);
        $this->info(($dry ? '[dry-run] ' : '') . "Client reminders: {$r['reminders']}, staff alerts: {$r['staff_alerts']}, markers cleared: {$r['cleared']}");

        return self::SUCCESS;
    }
}

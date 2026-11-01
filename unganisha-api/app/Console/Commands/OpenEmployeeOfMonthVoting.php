<?php

namespace App\Console\Commands;

use App\Models\CronLog;
use App\Models\EmployeeOfMonthCycle;
use App\Models\PayrollSettings;
use App\Models\User;
use App\Notifications\EmployeeOfMonthVotingOpenNotification;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Notification;

/**
 * Opens an "Employee of the Month" voting cycle for the month that just
 * ended, for every tenant that has opted in (PayrollSettings.eotm_enabled —
 * off by default, a tenant admin turns it on from Payroll > Settings) and
 * has at least 2 active staff (voting needs a candidate other than
 * yourself). Runs daily but only acts on the 1st-3rd
 * of the month — gated on the DAY, not on "did we already run today", so a
 * missed run on the 1st still opens the window (just with fewer days left)
 * instead of silently skipping the whole month. firstOrCreate on
 * (tenant_id, period_month_key) makes re-runs within that window a no-op.
 */
class OpenEmployeeOfMonthVoting extends Command
{
    protected $signature = 'eotm:open-voting';
    protected $description = 'Open Employee of the Month voting for the previous month (1st–3rd of this month only)';

    public function handle(): int
    {
        $startedAt = now();

        if ($startedAt->day > 3) {
            $this->info('Not within the 1st-3rd opening window — nothing to do.');
            return self::SUCCESS;
        }

        $periodMonthKey = $startedAt->copy()->subMonth()->format('Y-m');
        $votingOpensOn = $startedAt->copy()->startOfMonth();
        $votingClosesOn = $votingOpensOn->copy()->addDays(2);

        $enabledTenantIds = PayrollSettings::withoutGlobalScopes()->where('eotm_enabled', true)->pluck('tenant_id');

        $tenantIds = User::whereIn('tenant_id', $enabledTenantIds)->where('is_active', true)->select('tenant_id')
            ->groupBy('tenant_id')->havingRaw('count(*) >= 2')->pluck('tenant_id');

        $opened = 0;
        $errors = [];

        foreach ($tenantIds as $tenantId) {
            try {
                $cycle = EmployeeOfMonthCycle::withoutGlobalScopes()->firstOrCreate(
                    ['tenant_id' => $tenantId, 'period_month_key' => $periodMonthKey],
                    ['voting_opens_on' => $votingOpensOn, 'voting_closes_on' => $votingClosesOn, 'status' => 'open']
                );

                if ($cycle->wasRecentlyCreated) {
                    $opened++;
                    $staff = User::where('tenant_id', $tenantId)->where('is_active', true)->get();
                    Notification::send($staff, new EmployeeOfMonthVotingOpenNotification($cycle));
                }
            } catch (\Throwable $e) {
                $errors[] = "{$tenantId}: {$e->getMessage()}";
            }
        }

        $this->info("Opened {$opened} cycle(s) for {$periodMonthKey}.");

        CronLog::create([
            'tenant_id' => null,
            'command' => $this->signature,
            'description' => "Opened {$opened} Employee of the Month cycle(s) for {$periodMonthKey}" . ($errors ? ' with errors' : ''),
            'results' => ['opened' => $opened, 'errors' => $errors],
            'status' => $errors ? 'failed' : 'success',
            'started_at' => $startedAt,
            'finished_at' => now(),
        ]);

        return self::SUCCESS;
    }
}

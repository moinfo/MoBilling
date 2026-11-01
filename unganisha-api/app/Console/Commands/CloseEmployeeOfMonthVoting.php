<?php

namespace App\Console\Commands;

use App\Models\CronLog;
use App\Models\EmployeeOfMonthCycle;
use App\Models\User;
use App\Notifications\EmployeeOfMonthWinnerNotification;
use App\Services\EmployeeOfMonthService;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Notification;

/**
 * Tallies and closes every still-open cycle whose voting window has passed
 * (voting_closes_on < today) — not gated on "is today the 4th", so a missed
 * run still catches up correctly whenever it next runs. Creates the
 * winner's prize Commission immediately if a prize_amount was already set;
 * otherwise it's created later, the moment staff set the prize via the
 * admin screen (see EmployeeOfMonthService::maybeCreateOrUpdateCommission).
 */
class CloseEmployeeOfMonthVoting extends Command
{
    protected $signature = 'eotm:close-voting';
    protected $description = 'Tally and close Employee of the Month cycles whose voting window has ended';

    public function handle(EmployeeOfMonthService $service): int
    {
        $startedAt = now();
        $today = $startedAt->toDateString();

        $cycles = EmployeeOfMonthCycle::withoutGlobalScopes()
            ->where('status', 'open')->whereDate('voting_closes_on', '<', $today)->get();

        $closed = 0;
        $errors = [];

        foreach ($cycles as $cycle) {
            try {
                $service->tally($cycle);
                $closed++;

                $cycle = $cycle->fresh();
                $staff = User::where('tenant_id', $cycle->tenant_id)->where('is_active', true)->get();
                Notification::send($staff, new EmployeeOfMonthWinnerNotification($cycle));
            } catch (\Throwable $e) {
                $errors[] = "{$cycle->id}: {$e->getMessage()}";
            }
        }

        $this->info("Closed {$closed} cycle(s).");

        CronLog::create([
            'tenant_id' => null,
            'command' => $this->signature,
            'description' => "Closed {$closed} Employee of the Month cycle(s)" . ($errors ? ' with errors' : ''),
            'results' => ['closed' => $closed, 'errors' => $errors],
            'status' => $errors ? 'failed' : 'success',
            'started_at' => $startedAt,
            'finished_at' => now(),
        ]);

        return self::SUCCESS;
    }
}

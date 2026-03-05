<?php

namespace App\Console\Commands;

use App\Models\Client;
use App\Models\CronLog;
use App\Models\SatisfactionCall;
use App\Models\Tenant;
use Carbon\Carbon;
use Carbon\CarbonPeriod;
use Illuminate\Console\Command;

class ScheduleSatisfactionCalls extends Command
{
    protected $signature = 'satisfaction-calls:schedule';

    protected $description = 'Auto-schedule monthly satisfaction calls for all clients';

    public function handle(): int
    {
        $startedAt = now();
        $today = Carbon::today();
        $monthKey = $today->format('Y-m');

        try {
            // 1. Mark past-due "scheduled" calls as "missed"
            $missed = SatisfactionCall::withoutGlobalScopes()
                ->where('status', 'scheduled')
                ->whereDate('scheduled_date', '<', $today)
                ->update(['status' => 'missed']);

            // 2. Schedule calls for each active tenant
            $scheduled = 0;
            $tenants = Tenant::all();

            foreach ($tenants as $tenant) {
                if (!$tenant->hasAccess()) {
                    continue;
                }

                // Get active (non-deleted) clients for this tenant
                $clientIds = Client::withoutGlobalScopes()
                    ->where('tenant_id', $tenant->id)
                    ->whereNull('deleted_at')
                    ->pluck('id')
                    ->toArray();

                if (empty($clientIds)) {
                    continue;
                }

                // Find which clients already have a call for this month
                $existingClientIds = SatisfactionCall::withoutGlobalScopes()
                    ->where('tenant_id', $tenant->id)
                    ->where('month_key', $monthKey)
                    ->pluck('client_id')
                    ->toArray();

                $unscheduledClientIds = array_values(array_diff($clientIds, $existingClientIds));

                if (empty($unscheduledClientIds)) {
                    continue;
                }

                // Get remaining weekdays in the month (today through end of month)
                $endOfMonth = $today->copy()->endOfMonth();
                $weekdays = [];

                $period = CarbonPeriod::create($today, $endOfMonth);
                foreach ($period as $date) {
                    if ($date->isWeekday()) {
                        $weekdays[] = $date->toDateString();
                    }
                }

                if (empty($weekdays)) {
                    continue;
                }

                // Shuffle clients for fairness, then distribute evenly across weekdays
                shuffle($unscheduledClientIds);

                foreach ($unscheduledClientIds as $index => $clientId) {
                    $dayIndex = $index % count($weekdays);

                    try {
                        SatisfactionCall::withoutGlobalScopes()->create([
                            'tenant_id' => $tenant->id,
                            'client_id' => $clientId,
                            'scheduled_date' => $weekdays[$dayIndex],
                            'status' => 'scheduled',
                            'month_key' => $monthKey,
                        ]);
                        $scheduled++;
                    } catch (\Illuminate\Database\UniqueConstraintViolationException) {
                        // Unique constraint prevents duplicates — safe to skip
                    }
                }
            }

            $this->info("Missed: {$missed}, Scheduled: {$scheduled}");

            CronLog::create([
                'tenant_id' => null,
                'command' => $this->signature,
                'description' => "Marked {$missed} missed, scheduled {$scheduled} new satisfaction calls",
                'results' => [
                    'missed' => $missed,
                    'scheduled' => $scheduled,
                    'month_key' => $monthKey,
                ],
                'status' => 'success',
                'started_at' => $startedAt,
                'finished_at' => now(),
            ]);

            return self::SUCCESS;
        } catch (\Throwable $e) {
            CronLog::create([
                'tenant_id' => null,
                'command' => $this->signature,
                'description' => 'Failed to schedule satisfaction calls',
                'status' => 'failed',
                'error' => $e->getMessage(),
                'started_at' => $startedAt,
                'finished_at' => now(),
            ]);

            $this->error($e->getMessage());
            return self::FAILURE;
        }
    }
}

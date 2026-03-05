<?php

namespace App\Console\Commands;

use App\Models\Client;
use App\Models\CronLog;
use App\Models\SatisfactionCall;
use App\Models\Tenant;
use App\Models\User;
use App\Notifications\SatisfactionCallDailyReminderNotification;
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

                // Get active users for round-robin assignment
                $userIds = User::where('tenant_id', $tenant->id)
                    ->where('is_active', true)
                    ->whereNull('deleted_at')
                    ->pluck('id')
                    ->toArray();

                // Shuffle clients for fairness, then distribute evenly across weekdays
                shuffle($unscheduledClientIds);

                foreach ($unscheduledClientIds as $index => $clientId) {
                    $dayIndex = $index % count($weekdays);
                    $userId = !empty($userIds) ? $userIds[$index % count($userIds)] : null;

                    try {
                        SatisfactionCall::withoutGlobalScopes()->create([
                            'tenant_id' => $tenant->id,
                            'client_id' => $clientId,
                            'user_id' => $userId,
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

            // 3. Send daily reminders to users with calls today
            $reminded = 0;
            foreach ($tenants as $tenant) {
                if (!$tenant->hasAccess()) {
                    continue;
                }

                $todayCalls = SatisfactionCall::withoutGlobalScopes()
                    ->with('client')
                    ->where('tenant_id', $tenant->id)
                    ->where('status', 'scheduled')
                    ->whereDate('scheduled_date', $today)
                    ->whereNotNull('user_id')
                    ->get();

                $grouped = $todayCalls->groupBy('user_id');

                foreach ($grouped as $userId => $calls) {
                    $user = User::find($userId);
                    if (!$user) continue;

                    $user->notify(new SatisfactionCallDailyReminderNotification(
                        $tenant,
                        $calls->count(),
                        $calls,
                    ));
                    $reminded++;
                }
            }

            $this->info("Missed: {$missed}, Scheduled: {$scheduled}, Reminders: {$reminded}");

            CronLog::create([
                'tenant_id' => null,
                'command' => $this->signature,
                'description' => "Marked {$missed} missed, scheduled {$scheduled} new calls, sent {$reminded} reminders",
                'results' => [
                    'missed' => $missed,
                    'scheduled' => $scheduled,
                    'reminders_sent' => $reminded,
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

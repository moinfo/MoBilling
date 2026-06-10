<?php

namespace App\Console\Commands;

use App\Models\CronLog;
use App\Models\SystemVerification;
use App\Models\SystemVerificationReport;
use App\Models\Tenant;
use App\Notifications\VerificationReminderNotification;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Log;

class SendVerificationReminders extends Command
{
    /**
     * --second-reminder flag flips the notification copy to "Final
     * reminder" wording. Same command is scheduled twice (20:00 and 22:00)
     * with different flags.
     */
    protected $signature = 'verifications:send-reminders {--second-reminder}';

    protected $description = 'Notify staff whose assigned system verifications still have no report for today.';

    public function handle(): int
    {
        $startedAt = now();
        $isSecond = (bool) $this->option('second-reminder');
        $today = today()->toDateString();

        $tenantsTouched = 0;
        $usersNotified = 0;

        try {
            // Iterate every tenant. We bypass the tenant global scope because
            // the cron runs without auth context.
            $tenants = Tenant::withoutGlobalScopes()->get();

            foreach ($tenants as $tenant) {
                if (! $tenant->hasAccess()) {
                    continue;
                }

                // For each tenant, find active systems whose assigned staff
                // hasn't reported today, group by user.
                $pendingByUser = [];

                $active = SystemVerification::withoutGlobalScopes()
                    ->where('tenant_id', $tenant->id)
                    ->where('is_active', true)
                    ->whereNotNull('assigned_user_id')
                    ->with('assignedUser:id,name,email,tenant_id')
                    ->get();

                foreach ($active as $sv) {
                    $reported = SystemVerificationReport::withoutGlobalScopes()
                        ->where('system_verification_id', $sv->id)
                        ->whereDate('report_date', $today)
                        ->exists();

                    if (! $reported) {
                        $pendingByUser[$sv->assigned_user_id][] = $sv;
                    }
                }

                if (empty($pendingByUser)) {
                    continue;
                }

                $tenantsTouched++;
                foreach ($pendingByUser as $userId => $pending) {
                    $user = $pending[0]->assignedUser; // already eager-loaded
                    if (! $user) {
                        continue;
                    }
                    try {
                        $user->notify(new VerificationReminderNotification($tenant, $pending, $isSecond));
                        $usersNotified++;
                    } catch (\Throwable $e) {
                        Log::error('Failed to send verification reminder', [
                            'tenant_id' => $tenant->id,
                            'user_id' => $userId,
                            'exception' => $e,
                        ]);
                    }
                }
            }

            $this->info("Reminders sent to {$usersNotified} users across {$tenantsTouched} tenants");

            CronLog::create([
                'tenant_id' => null,
                'command' => $this->signature,
                'description' => ($isSecond ? '[Final] ' : '') . "Notified {$usersNotified} users across {$tenantsTouched} tenants of pending verifications",
                'results' => [
                    'users_notified' => $usersNotified,
                    'tenants_touched' => $tenantsTouched,
                    'second_reminder' => $isSecond,
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
                'description' => 'Failed to send verification reminders',
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

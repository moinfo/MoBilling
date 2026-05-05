<?php

namespace App\Console\Commands;

use App\Models\CronLog;
use App\Models\StaffReport;
use App\Models\StaffReportSettings;
use App\Models\Tenant;
use App\Models\User;
use App\Notifications\StaffReportDeadlineReminderNotification;
use Carbon\Carbon;
use Illuminate\Console\Command;

class SendStaffReportReminders extends Command
{
    protected $signature = 'staff-reports:send-reminders';

    protected $description = 'Send deadline reminders to staff who have not yet submitted their reports';

    public function handle(): int
    {
        $startedAt = now();
        $today     = Carbon::today();
        $sent      = 0;

        try {
            $tenants = Tenant::all();

            foreach ($tenants as $tenant) {
                if (!$tenant->hasAccess()) {
                    continue;
                }

                $settings = StaffReportSettings::withoutGlobalScopes()
                    ->where('tenant_id', $tenant->id)
                    ->first();

                if (!$settings) {
                    continue;
                }

                // Resolve which staff can submit reports for this tenant
                $staffIds = $this->getSubmitterIds($tenant->id);

                if ($staffIds->isEmpty()) {
                    continue;
                }

                $sent += $this->sendForType($tenant, $settings, $staffIds, 'daily', $today);
                $sent += $this->sendForType($tenant, $settings, $staffIds, 'weekly', $today);
                $sent += $this->sendForType($tenant, $settings, $staffIds, 'monthly', $today);
            }

            CronLog::withoutGlobalScopes()->create([
                'command'      => $this->signature,
                'status'       => 'success',
                'records'      => $sent,
                'started_at'   => $startedAt,
                'completed_at' => now(),
            ]);

            $this->info("Sent {$sent} staff report reminder(s).");
            return 0;
        } catch (\Throwable $e) {
            CronLog::withoutGlobalScopes()->create([
                'command'      => $this->signature,
                'status'       => 'failed',
                'message'      => $e->getMessage(),
                'started_at'   => $startedAt,
                'completed_at' => now(),
            ]);

            $this->error($e->getMessage());
            return 1;
        }
    }

    private function sendForType(Tenant $tenant, StaffReportSettings $settings, $staffIds, string $type, Carbon $today): int
    {
        [$isDueToday, $periodDate, $deadlineTime, $periodLabel] = match ($type) {
            'daily'   => $this->dailyInfo($settings, $today),
            'weekly'  => $this->weeklyInfo($settings, $today),
            'monthly' => $this->monthlyInfo($settings, $today),
        };

        if (!$isDueToday) {
            return 0;
        }

        // Find staff who have NOT submitted this period's report
        $submitted = StaffReport::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)
            ->where('report_type', $type)
            ->where('period_date', $periodDate)
            ->pluck('user_id')
            ->all();

        $pending = User::withoutGlobalScopes()
            ->where('tenant_id', $tenant->id)
            ->whereIn('id', $staffIds)
            ->whereNotIn('id', $submitted)
            ->get();

        $notification = new StaffReportDeadlineReminderNotification(
            $tenant,
            $type,
            $periodLabel,
            $deadlineTime,
        );

        foreach ($pending as $user) {
            $user->notify($notification);
        }

        return $pending->count();
    }

    private function dailyInfo(StaffReportSettings $s, Carbon $today): array
    {
        // Always due today — remind every morning
        $deadlineTime = $s->daily_deadline_time;
        $periodLabel  = $today->format('D, j M Y');

        return [true, $today->toDateString(), $deadlineTime, $periodLabel];
    }

    private function weeklyInfo(StaffReportSettings $s, Carbon $today): array
    {
        // Due on the deadline day of the week (1=Mon … 7=Sun)
        $isDue       = $today->dayOfWeekIso === $s->weekly_deadline_day;
        $weekStart   = $today->copy()->startOfWeek(Carbon::MONDAY)->toDateString();
        $periodLabel = 'Week ' . $today->isoWeek() . ' · ' . $today->copy()->startOfWeek()->format('j M') . '–' . $today->copy()->endOfWeek()->format('j M Y');

        return [$isDue, $weekStart, $s->weekly_deadline_time, $periodLabel];
    }

    private function monthlyInfo(StaffReportSettings $s, Carbon $today): array
    {
        // Due on the configured day of month — or last day if month is shorter
        $dueDay      = min($s->monthly_deadline_day, $today->daysInMonth);
        $isDue       = $today->day === $dueDay;
        $monthStart  = $today->copy()->startOfMonth()->toDateString();
        $periodLabel = $today->format('M Y');

        return [$isDue, $monthStart, $s->monthly_deadline_time, $periodLabel];
    }

    private function getSubmitterIds(string $tenantId)
    {
        // Get role IDs that have the staff_reports.submit permission
        $roleIds = \DB::table('role_permissions')
            ->join('permissions', 'permissions.id', '=', 'role_permissions.permission_id')
            ->join('roles', 'roles.id', '=', 'role_permissions.role_id')
            ->where('roles.tenant_id', $tenantId)
            ->where('permissions.name', 'staff_reports.submit')
            ->pluck('role_permissions.role_id');

        if ($roleIds->isEmpty()) {
            return collect();
        }

        return User::withoutGlobalScopes()
            ->where('tenant_id', $tenantId)
            ->where('is_active', true)
            ->whereIn('role_id', $roleIds)
            ->pluck('id');
    }
}
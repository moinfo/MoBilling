<?php

namespace App\Console\Commands;

use App\Models\StaffReport;
use App\Models\StaffReportPenalty;
use App\Models\StaffReportSettings;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Charge deductions for MISSING staff reports once each period's deadline has
 * passed. Late-report deductions are recorded at submission time
 * (StaffReportsController@store); this handles the "never submitted" case.
 *
 * Runs daily. Idempotent — the (user, type, penalty_type, period) unique index
 * means a re-run never double-charges.
 */
class ApplyStaffReportPenalties extends Command
{
    protected $signature = 'staff-reports:apply-penalties {--dry-run : Report what would be charged without writing}';
    protected $description = 'Charge deductions for missing (unsubmitted) staff reports past their deadline';

    public function handle(): int
    {
        $dry = (bool) $this->option('dry-run');
        $now = now();
        $charged = 0;

        $tenants = DB::table('tenants')->pluck('id');
        foreach ($tenants as $tenantId) {
            $s = StaffReportSettings::withoutGlobalScopes()->where('tenant_id', $tenantId)->first();
            if (!$s || !$s->penalties_enabled) {
                continue;
            }

            $staffIds = $this->submitterIds($tenantId);
            if ($staffIds->isEmpty()) {
                continue;
            }

            // ── Daily: charge for YESTERDAY (a completed weekday with no report) ──
            $yesterday = $now->copy()->subDay();
            if ($yesterday->isWeekday() && (float) $s->penalty_missing_daily > 0) {
                $charged += $this->chargeMissing(
                    $tenantId, $staffIds, 'daily', $yesterday->toDateString(),
                    (float) $s->penalty_missing_daily, 'Missing daily report (' . $yesterday->format('D, j M') . ')', $dry
                );
            }

            // ── Weekly: current week, once its deadline has passed ──
            $weekStart = $now->copy()->startOfWeek(Carbon::MONDAY);
            $weekDeadline = $weekStart->copy()->addDays($s->weekly_deadline_day - 1)->setTimeFromTimeString($s->weekly_deadline_time);
            if ($now->gt($weekDeadline) && (float) $s->penalty_missing_weekly > 0) {
                $charged += $this->chargeMissing(
                    $tenantId, $staffIds, 'weekly', $weekStart->toDateString(),
                    (float) $s->penalty_missing_weekly, 'Missing weekly report (wk of ' . $weekStart->format('j M') . ')', $dry
                );
            }

            // ── Monthly: current month, once its deadline has passed ──
            $monthStart = $now->copy()->startOfMonth();
            $dueDay = min($s->monthly_deadline_day, $now->daysInMonth);
            $monthDeadline = $monthStart->copy()->addDays($dueDay - 1)->setTimeFromTimeString($s->monthly_deadline_time);
            if ($now->gt($monthDeadline) && (float) $s->penalty_missing_monthly > 0) {
                $charged += $this->chargeMissing(
                    $tenantId, $staffIds, 'monthly', $monthStart->toDateString(),
                    (float) $s->penalty_missing_monthly, 'Missing monthly report (' . $monthStart->format('M Y') . ')', $dry
                );
            }
        }

        $this->info($dry ? "Dry run: {$charged} penalties would be charged." : "Charged {$charged} penalties.");
        return self::SUCCESS;
    }

    /** Charge every staff member who has no report of $type for $periodDate. */
    private function chargeMissing($tenantId, $staffIds, string $type, string $periodDate, float $amount, string $notes, bool $dry): int
    {
        $submitted = StaffReport::withoutGlobalScopes()
            ->where('tenant_id', $tenantId)
            ->where('report_type', $type)
            ->where('period_date', $periodDate)
            ->pluck('user_id')->all();

        $missing = $staffIds->diff($submitted);
        if ($missing->isEmpty()) {
            return 0;
        }

        if ($dry) {
            $this->line("  {$type} {$periodDate}: {$missing->count()} missing × " . number_format($amount));
            return $missing->count();
        }

        $n = 0;
        foreach ($missing as $uid) {
            $created = StaffReportPenalty::firstOrCreate(
                ['user_id' => $uid, 'report_type' => $type, 'penalty_type' => 'missing', 'period_date' => $periodDate],
                ['tenant_id' => $tenantId, 'amount' => $amount, 'notes' => $notes],
            );
            if ($created->wasRecentlyCreated) {
                $n++;
            }
        }
        return $n;
    }

    private function submitterIds(string $tenantId)
    {
        $roleIds = DB::table('role_permissions')
            ->join('roles', 'roles.id', '=', 'role_permissions.role_id')
            ->join('permissions', 'permissions.id', '=', 'role_permissions.permission_id')
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

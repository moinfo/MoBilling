<?php

namespace App\Console\Commands;

use App\Models\Attendance;
use App\Models\AttendancePenalty;
use App\Models\AttendanceSettings;
use App\Models\StaffReportHoliday;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Charge attendance deductions once a working day's check-out time has passed:
 * absent (no check-in — even if they checked out), late (in after check-in
 * time), left early (out before check-out time), and no check-out. Backfills
 * the current month; idempotent via the (user, date, type) unique index.
 */
class ApplyAttendancePenalties extends Command
{
    protected $signature = 'attendance:apply-penalties {--dry-run}';
    protected $description = 'Charge attendance deductions (absent/late/left-early/no-checkout)';

    public function handle(): int
    {
        $dry = (bool) $this->option('dry-run');
        $now = now();
        $charged = 0;

        foreach (DB::table('tenants')->pluck('id') as $tenantId) {
            $s = AttendanceSettings::withoutGlobalScopes()->where('tenant_id', $tenantId)->first();
            if (!$s || !$s->penalties_enabled) {
                continue;
            }

            $workDays = $s->working_days ?: [1, 2, 3, 4, 5, 6];
            $holidays = StaffReportHoliday::withoutGlobalScopes()->where('tenant_id', $tenantId)
                ->pluck('date')->map(fn ($d) => Carbon::parse($d)->toDateString())->flip();

            $userIds = User::withoutGlobalScopes()->where('tenant_id', $tenantId)
                ->where('is_active', true)->pluck('id');
            if ($userIds->isEmpty()) {
                continue;
            }

            // Start the day AFTER attendance was enabled — never backfill
            // absences for days before the feature existed (or its launch day).
            $monthStart = $now->copy()->startOfMonth();
            $begin = $s->created_at ? $s->created_at->copy()->addDay()->startOfDay() : $monthStart;
            if ($begin->lt($monthStart)) {
                $begin = $monthStart;
            }
            for ($d = $begin->copy(); $d->lte($now); $d->addDay()) {
                if (!in_array($d->dayOfWeekIso, $workDays) || $holidays->has($d->toDateString())) {
                    continue;
                }
                // Only assess a day once its check-out time has passed.
                $checkoutDeadline = $d->copy()->setTimeFromTimeString($s->check_out_time);
                if (!$now->gt($checkoutDeadline)) {
                    continue;
                }

                $records = Attendance::withoutGlobalScopes()->where('tenant_id', $tenantId)
                    ->whereDate('date', $d->toDateString())->get()->keyBy('user_id');

                $inCut  = $d->copy()->setTimeFromTimeString($s->check_in_time);
                $outCut = $checkoutDeadline;

                foreach ($userIds as $uid) {
                    $att = $records->get($uid);
                    $charges = [];

                    if (!$att || !$att->check_in_at) {
                        // No check-in → absent (even if they checked out).
                        $charges['absent'] = [(float) $s->penalty_absent, 'Absent (no check-in)'];
                    } else {
                        if ($att->check_in_at->gt($inCut)) {
                            $charges['late'] = [(float) $s->penalty_late, 'Late check-in (' . $att->check_in_at->format('H:i') . ')'];
                        }
                        if (!$att->check_out_at) {
                            $charges['no_checkout'] = [(float) $s->penalty_no_checkout, 'No check-out'];
                        } elseif ($att->check_out_at->lt($outCut)) {
                            $charges['left_early'] = [(float) $s->penalty_left_early, 'Left early (' . $att->check_out_at->format('H:i') . ')'];
                        }
                    }

                    foreach ($charges as $type => [$amount, $note]) {
                        if ($amount <= 0) {
                            continue;
                        }
                        if ($dry) {
                            $charged++;
                            continue;
                        }
                        $created = AttendancePenalty::firstOrCreate(
                            ['user_id' => $uid, 'date' => $d->toDateString(), 'penalty_type' => $type],
                            ['tenant_id' => $tenantId, 'amount' => $amount, 'notes' => $note],
                        );
                        if ($created->wasRecentlyCreated) {
                            $charged++;
                        }
                    }
                }
            }
        }

        $this->info($dry ? "Dry run: {$charged} attendance penalties." : "Charged {$charged} attendance penalties.");
        return self::SUCCESS;
    }
}

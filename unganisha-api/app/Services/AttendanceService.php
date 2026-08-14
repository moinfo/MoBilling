<?php

namespace App\Services;

use App\Models\Attendance;
use App\Models\AttendancePenalty;
use App\Models\AttendanceSettings;
use App\Models\User;

/**
 * `formatDay()`/`settings()` moved here verbatim from AttendanceController
 * (pure relocation, no logic change — every call site there now delegates
 * to this service instead of a private method) so `markExcused()` can be
 * shared by both AttendanceController::record() (clerk manually marks a
 * day) and LeaveRequestController::review() (an approved leave request
 * marks every day in its range) without either duplicating the other's
 * upsert-and-penalty-cleanup logic.
 */
class AttendanceService
{
    /**
     * Mark one day as excused (leave/sick/field) for a user — a free day,
     * never late/absent/left-early/no-checkout (formatDay() confirms every
     * one of those flags is forced false whenever Attendance::isExcused()
     * is true), so any unwaived penalty for that date is now stale and
     * gets dropped unconditionally.
     */
    public function markExcused(User $user, string $date, string $status, ?string $note = null): Attendance
    {
        $att = Attendance::firstOrNew(['user_id' => $user->id, 'date' => $date]);
        $att->tenant_id ??= $user->tenant_id;
        $att->status = $status;
        $att->status_note = $note;
        $att->check_in_at = null;
        $att->check_out_at = null;
        $att->save();

        AttendancePenalty::where('user_id', $att->user_id)
            ->whereDate('date', $att->date->toDateString())
            ->where('waived', false)
            ->delete();

        return $att;
    }

    /** Status flags for a day, evaluated against the settings' times. */
    public function formatDay(Attendance $a, AttendanceSettings $s): array
    {
        $excused = $a->isExcused();   // leave / sick / field duty → a free day, no marks

        $late = !$excused && $a->check_in_at
            && $a->check_in_at->gt($a->date->copy()->setTimeFromTimeString($s->check_in_time));
        $leftEarly = !$excused && $a->check_out_at
            && $a->check_out_at->lt($a->date->copy()->setTimeFromTimeString($s->check_out_time));

        return [
            'id'           => $a->id,
            'date'         => $a->date->format('Y-m-d'),
            'status'       => $a->status,               // null | leave | sick | field
            'status_note'  => $a->status_note,
            'check_in_at'  => $a->check_in_at?->format('H:i'),
            'check_out_at' => $a->check_out_at?->format('H:i'),
            'absent'       => !$excused && !$a->check_in_at,  // no check-in = absent (unless excused)
            'late'         => (bool) $late,
            'left_early'   => (bool) $leftEarly,
            'no_checkout'  => !$excused && $a->check_in_at && !$a->check_out_at,
        ];
    }

    public function settings(): AttendanceSettings
    {
        return AttendanceSettings::firstOrCreate([], [
            'check_in_time'  => '07:30',
            'check_out_time' => '17:00',
            'penalties_enabled'   => true,
            'penalty_absent'      => 5000,
            'penalty_late'        => 2000,
            'penalty_left_early'  => 2000,
            'penalty_no_checkout' => 2000,
            'working_days'        => [1, 2, 3, 4, 5, 6],
        ]);
    }
}

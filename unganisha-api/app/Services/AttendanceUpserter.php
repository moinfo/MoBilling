<?php

namespace App\Services;

use App\Models\Attendance;
use Carbon\Carbon;

/**
 * Shared rule for folding swipe timestamps into a day's attendance: the
 * earliest time becomes the check-in, the latest becomes the check-out, and a
 * single timestamp is a check-in with no check-out. An excused day
 * (leave/sick/field) is never overwritten. Used by both the live device import
 * and the iVMS-4200 sheet import so they behave identically.
 *
 * BelongsToTenant is inert in the console/public contexts these run in, so
 * queries scope tenant_id explicitly via withoutGlobalScopes().
 */
class AttendanceUpserter
{
    /**
     * @param  Carbon[]  $times  one or more swipe timestamps for that day
     * @return bool  true if a record was written, false if skipped (excused / no times)
     */
    public function applyDay(string $tenantId, string $userId, string $date, array $times): bool
    {
        $times = array_values(array_filter($times));
        if (!$times) {
            return false;
        }

        $att = Attendance::withoutGlobalScopes()
            ->where('user_id', $userId)->whereDate('date', $date)->first()
            ?? new Attendance(['user_id' => $userId, 'date' => $date]);

        // Never overwrite an excused day (leave / sick / field duty).
        if ($att->exists && $att->isExcused()) {
            return false;
        }

        // Consider existing marks alongside the new times so imports are idempotent.
        $all = collect($times);
        if ($att->check_in_at)  { $all->push($att->check_in_at); }
        if ($att->check_out_at) { $all->push($att->check_out_at); }
        $all = $all->map(fn ($t) => $t instanceof Carbon ? $t : Carbon::parse($t))->sort()->values();

        $earliest = $all->first();
        $latest   = $all->last();

        $att->tenant_id ??= $tenantId;
        $att->check_in_at  = $earliest;
        $att->check_out_at = $latest->gt($earliest) ? $latest : null;   // single swipe = no check-out
        $att->save();

        return true;
    }
}

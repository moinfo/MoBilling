<?php

namespace App\Services;

use App\Models\Attendance;
use Carbon\Carbon;

/**
 * Shared rule for folding swipe timestamps into a day's attendance: punches
 * BEFORE the split time count as check-in candidates (earliest wins), punches
 * AT/AFTER it count as check-out candidates (latest wins). This stops a midday
 * exit from being read as the day's check-out when someone forgets to punch
 * out in the evening. An excused day (leave/sick/field) is never overwritten.
 * Used by both the live device import and the iVMS-4200 sheet import so they
 * behave identically.
 *
 * BelongsToTenant is inert in the console/public contexts these run in, so
 * queries scope tenant_id explicitly via withoutGlobalScopes().
 */
class AttendanceUpserter
{
    /** Punches before this hour are check-ins; from it onwards, check-outs. */
    public const SPLIT_TIME = '15:00';
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

        $split = Carbon::parse($date . ' ' . self::SPLIT_TIME);
        $ins  = $all->filter(fn ($t) => $t->lt($split));
        $outs = $all->filter(fn ($t) => $t->gte($split));

        $att->tenant_id ??= $tenantId;
        $att->check_in_at  = $ins->first();    // earliest morning punch (null = no check-in)
        $att->check_out_at = $outs->last();    // latest evening punch (null = forgot to punch out)
        $att->save();

        return true;
    }
}

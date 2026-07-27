<?php

namespace App\Services;

use App\Models\AttendanceDeviceEvent;
use App\Models\User;
use Carbon\Carbon;

/**
 * Folds captured HIKVISION device events into attendance records.
 *
 * Each staff member is linked to the employee number their terminal reports
 * (users.device_employee_no). For every unprocessed event that resolves to a
 * linked, active user we set that day's earliest swipe as the check-in and the
 * latest as the check-out. Events whose employee number isn't linked yet are
 * left unprocessed so they import automatically once the mapping is added.
 *
 * Runs from three places: inline on capture (best-effort), the
 * attendance:import-device-events schedule, and the Device tab "Import now"
 * button. BelongsToTenant is inert here (public/console context) so every query
 * scopes tenant_id explicitly via withoutGlobalScopes().
 */
class AttendanceDeviceImporter
{
    public function __construct(private AttendanceUpserter $upserter) {}

    /**
     * Drain a tenant's unprocessed events into attendance.
     *
     * @return array{matched:int,unmatched:int,days:int}
     */
    public function drainTenant(string $tenantId): array
    {
        $events = AttendanceDeviceEvent::withoutGlobalScopes()
            ->where('tenant_id', $tenantId)
            ->where('processed', false)
            ->whereNotNull('employee_no')
            ->whereNotNull('event_time')
            ->orderBy('event_time')
            ->get();

        if ($events->isEmpty()) {
            return ['matched' => 0, 'unmatched' => 0, 'days' => 0];
        }

        // employee number → active user id
        $byEmployeeNo = User::withoutGlobalScopes()
            ->where('tenant_id', $tenantId)
            ->where('is_active', true)
            ->whereNotNull('device_employee_no')
            ->pluck('id', 'device_employee_no');

        $matched = 0;
        $unmatched = 0;
        $processedIds = [];
        // grouped[userId][Y-m-d] = ['times' => Carbon[], 'events' => id[]]
        $grouped = [];

        foreach ($events as $e) {
            $uid = $byEmployeeNo->get((string) $e->employee_no);
            if (!$uid) {
                $unmatched++;                 // leave unprocessed — imports once linked
                continue;
            }
            $matched++;
            $t = Carbon::parse($e->event_time);
            $day = $t->toDateString();
            $grouped[$uid][$day]['times'][] = $t;
            $grouped[$uid][$day]['events'][] = $e->id;
        }

        $days = 0;
        foreach ($grouped as $uid => $perDay) {
            foreach ($perDay as $day => $bucket) {
                // Excused days are skipped inside applyDay, but the events are still
                // "handled" — mark them processed either way so they don't recur.
                if ($this->upserter->applyDay($tenantId, $uid, $day, $bucket['times'])) {
                    $days++;
                }
                array_push($processedIds, ...$bucket['events']);
            }
        }

        if ($processedIds) {
            AttendanceDeviceEvent::withoutGlobalScopes()
                ->whereIn('id', $processedIds)->update(['processed' => true]);
        }

        return ['matched' => $matched, 'unmatched' => $unmatched, 'days' => $days];
    }
}

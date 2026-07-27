<?php

namespace App\Console\Commands;

use App\Services\AttendanceDeviceImporter;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Drains captured HIKVISION events into attendance for every tenant. Scheduled
 * frequently so device swipes appear on staff dashboards near real-time; also
 * runnable manually. Idempotent — processed events are skipped.
 */
class ImportDeviceAttendance extends Command
{
    protected $signature = 'attendance:import-device-events';
    protected $description = 'Fold captured attendance-device events into attendance records';

    public function handle(AttendanceDeviceImporter $importer): int
    {
        $matched = 0;
        $days = 0;
        foreach (DB::table('tenants')->pluck('id') as $tenantId) {
            $res = $importer->drainTenant($tenantId);
            $matched += $res['matched'];
            $days += $res['days'];
        }
        $this->info("Imported {$matched} events across {$days} staff-days.");
        return self::SUCCESS;
    }
}

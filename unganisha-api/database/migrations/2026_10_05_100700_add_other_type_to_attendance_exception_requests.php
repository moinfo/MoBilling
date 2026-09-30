<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /**
     * A third explanation type for a day that isn't cleanly "ruhusa" or
     * "nje ya kazi" — the employee just writes their own reason, and
     * approving/rejecting it is the reviewer's explicit charge/no-charge
     * call (AttendanceExceptionController::review() waives that day's
     * penalty on approval but — unlike 'leave'/'field' — never rewrites
     * Attendance::status, since there's no real category to record it as).
     */
    public function up(): void
    {
        DB::statement("ALTER TABLE attendance_exception_requests MODIFY COLUMN type ENUM('leave','field','other') NOT NULL");
    }

    public function down(): void
    {
        DB::statement("UPDATE attendance_exception_requests SET type = 'field' WHERE type = 'other'");
        DB::statement("ALTER TABLE attendance_exception_requests MODIFY COLUMN type ENUM('leave','field') NOT NULL");
    }
};

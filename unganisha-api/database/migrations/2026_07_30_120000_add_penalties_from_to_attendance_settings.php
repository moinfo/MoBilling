<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Explicit start date for attendance deductions. Null keeps the default
 * (the day after the settings were created — no pre-launch backfill).
 * Set to 2026-07-01 per management's decision to charge the whole of July
 * now that device data covers it.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('attendance_settings', function (Blueprint $table) {
            $table->date('penalties_from')->nullable()->after('penalties_enabled');
        });
        DB::table('attendance_settings')->update(['penalties_from' => '2026-07-01']);
    }

    public function down(): void
    {
        Schema::table('attendance_settings', function (Blueprint $table) {
            $table->dropColumn('penalties_from');
        });
    }
};

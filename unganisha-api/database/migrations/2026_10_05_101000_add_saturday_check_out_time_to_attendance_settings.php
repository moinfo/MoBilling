<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Saturday is often a half-day — a separate, earlier check-out target so
 * leaving on time for a half-day isn't flagged/penalized as "left early"
 * against the normal full-day check_out_time. Null keeps today's behavior
 * (same target every working day).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('attendance_settings', function (Blueprint $table) {
            $table->time('saturday_check_out_time')->nullable()->after('check_out_time');
        });
    }

    public function down(): void
    {
        Schema::table('attendance_settings', function (Blueprint $table) {
            $table->dropColumn('saturday_check_out_time');
        });
    }
};

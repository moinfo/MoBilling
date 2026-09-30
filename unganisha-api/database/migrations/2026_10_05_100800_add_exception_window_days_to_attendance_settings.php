<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A day in month M may only be self-service explained (AttendanceException
 * Request) from the 1st through this many days into month M+1 — a payroll
 * dispute-window cutoff, configurable per tenant like the penalty amounts.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('attendance_settings', function (Blueprint $table) {
            $table->unsignedTinyInteger('exception_window_days')->default(5)->after('penalty_no_checkout');
        });
    }

    public function down(): void
    {
        Schema::table('attendance_settings', function (Blueprint $table) {
            $table->dropColumn('exception_window_days');
        });
    }
};

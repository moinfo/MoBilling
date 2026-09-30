<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The auto-computed "1st–Nth of next month" window (exception_window_days)
 * left NO day ever explainable on most real calendar dates — e.g. on the
 * 30th, last month's window had already closed and this month's hasn't
 * opened, so every submission failed "window closed". Replaced with a
 * window the admin opens explicitly: a from/to date range (when
 * submissions are accepted) plus which month is under review — e.g.
 * "Oct 1–5, reviewing September" — set right before running payroll,
 * cleared/left null the rest of the time (no active window = closed).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('attendance_settings', function (Blueprint $table) {
            $table->dropColumn('exception_window_days');
            $table->date('exception_window_from')->nullable()->after('penalty_no_checkout');
            $table->date('exception_window_to')->nullable()->after('exception_window_from');
            $table->date('exception_review_month')->nullable()->after('exception_window_to');
        });
    }

    public function down(): void
    {
        Schema::table('attendance_settings', function (Blueprint $table) {
            $table->dropColumn(['exception_window_from', 'exception_window_to', 'exception_review_month']);
            $table->unsignedTinyInteger('exception_window_days')->default(5)->after('penalty_no_checkout');
        });
    }
};

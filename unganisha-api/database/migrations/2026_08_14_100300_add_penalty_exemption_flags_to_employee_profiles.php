<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Same opt-out shape as subject_to_paye: a per-employee exception so
 * attendance/late-report penalties can be waived from payroll entirely
 * for someone (e.g. a role not tracked by the fingerprint device), not
 * just per individual penalty row. Default true so existing behavior is
 * unchanged until someone explicitly opts an employee out.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('employee_profiles', function (Blueprint $table) {
            $table->boolean('subject_to_attendance_penalty')->default(true)->after('subject_to_paye');
            $table->boolean('subject_to_report_penalty')->default(true)->after('subject_to_paye');
        });
    }

    public function down(): void
    {
        Schema::table('employee_profiles', function (Blueprint $table) {
            $table->dropColumn(['subject_to_attendance_penalty', 'subject_to_report_penalty']);
        });
    }
};

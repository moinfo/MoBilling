<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Not every employee is subject to every statutory deduction (e.g. a
 * non-NSSF-member expatriate, or a category the employer has agreed is
 * PAYE-exempt) — per-employee opt-out, mirroring how Allowances/Deductions
 * are individually subscribed rather than blanket-applied. Default true
 * on every column so existing payroll behavior is unchanged until someone
 * explicitly opts an employee out.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('employee_profiles', function (Blueprint $table) {
            $table->boolean('subject_to_paye')->default(true)->after('termination_date');
            $table->boolean('subject_to_nssf')->default(true)->after('termination_date');
            $table->boolean('subject_to_wcf')->default(true)->after('termination_date');
            $table->boolean('subject_to_sdl')->default(true)->after('termination_date');
        });
    }

    public function down(): void
    {
        Schema::table('employee_profiles', function (Blueprint $table) {
            $table->dropColumn(['subject_to_paye', 'subject_to_nssf', 'subject_to_wcf', 'subject_to_sdl']);
        });
    }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * NSSF/WCF/SDL moved into the statutory_rates catalog (see the two
 * preceding migrations) — these fixed columns are now redundant. Safe to
 * drop outright: this whole payroll feature shipped minutes ago in this
 * same session, no real payroll run has used them.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('payroll_settings', function (Blueprint $table) {
            $table->dropColumn(['nssf_employee_percent', 'nssf_employer_percent', 'wcf_percent', 'sdl_percent']);
        });

        Schema::table('employee_profiles', function (Blueprint $table) {
            $table->dropColumn(['subject_to_nssf', 'subject_to_wcf', 'subject_to_sdl']);
        });
    }

    public function down(): void
    {
        Schema::table('payroll_settings', function (Blueprint $table) {
            $table->decimal('nssf_employee_percent', 5, 2)->default(10.00);
            $table->decimal('nssf_employer_percent', 5, 2)->default(10.00);
            $table->decimal('wcf_percent', 5, 2)->default(0.50);
            $table->decimal('sdl_percent', 5, 2)->default(3.50);
        });

        Schema::table('employee_profiles', function (Blueprint $table) {
            $table->boolean('subject_to_nssf')->default(true);
            $table->boolean('subject_to_wcf')->default(true);
            $table->boolean('subject_to_sdl')->default(true);
        });
    }
};

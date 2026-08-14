<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Replaces the fixed nssf_employee_amount/nssf_employer_amount/wcf_amount/
 * sdl_amount columns with generic breakdowns so a payslip can reflect
 * however many statutory_rates entries a tenant has configured (not just
 * exactly three). No real payslip data exists yet to migrate — safe drop.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('payslips', function (Blueprint $table) {
            $table->dropColumn(['nssf_employee_amount', 'nssf_employer_amount', 'wcf_amount', 'sdl_amount']);
        });

        Schema::table('payslips', function (Blueprint $table) {
            $table->decimal('statutory_employee_total', 12, 2)->default(0)->after('taxable_income');
            $table->json('statutory_employee_breakdown')->nullable()->after('statutory_employee_total');
            $table->decimal('statutory_employer_total', 12, 2)->default(0)->after('employer_cost_total');
            $table->json('statutory_employer_breakdown')->nullable()->after('statutory_employer_total');
        });
    }

    public function down(): void
    {
        Schema::table('payslips', function (Blueprint $table) {
            $table->dropColumn(['statutory_employee_total', 'statutory_employee_breakdown', 'statutory_employer_total', 'statutory_employer_breakdown']);
        });

        Schema::table('payslips', function (Blueprint $table) {
            $table->decimal('nssf_employee_amount', 12, 2)->default(0);
            $table->decimal('nssf_employer_amount', 12, 2)->default(0);
            $table->decimal('wcf_amount', 12, 2)->default(0);
            $table->decimal('sdl_amount', 12, 2)->default(0);
        });
    }
};

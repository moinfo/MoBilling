<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A frozen snapshot per employee per run — never recalculated from
 * current settings after generation, so a later rate/salary change never
 * silently rewrites history. nssf_employer_amount/wcf_amount/sdl_amount
 * are EMPLOYER costs, informational only — never subtracted from
 * net_pay (see PayrollCalculationService).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('payslips', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('payroll_run_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('user_id')->constrained()->cascadeOnDelete();

            $table->decimal('basic_salary', 12, 2);
            $table->decimal('allowances_total', 12, 2)->default(0);
            $table->json('allowances_breakdown')->nullable();
            $table->decimal('gross_pay', 12, 2);

            $table->decimal('nssf_employee_amount', 12, 2)->default(0);
            $table->decimal('taxable_income', 12, 2);
            $table->decimal('paye_amount', 12, 2)->default(0);
            $table->decimal('other_deductions_total', 12, 2)->default(0);
            $table->json('deductions_breakdown')->nullable();

            $table->decimal('net_pay', 12, 2);

            $table->decimal('nssf_employer_amount', 12, 2)->default(0);
            $table->decimal('wcf_amount', 12, 2)->default(0);
            $table->decimal('sdl_amount', 12, 2)->default(0);
            $table->decimal('employer_cost_total', 12, 2)->default(0);

            $table->timestamps();

            $table->unique(['payroll_run_id', 'user_id']);
            $table->index('tenant_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('payslips');
    }
};

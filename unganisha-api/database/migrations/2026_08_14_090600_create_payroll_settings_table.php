<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * One row per tenant (firstOrCreate, mirrors AttendanceSettings). Every
 * rate here is tenant-editable via Settings — PAYE brackets, NSSF/WCF/SDL
 * percentages change with Tanzania's annual Finance Act, so nothing about
 * current correctness is hardcoded in application code. Seeded defaults
 * (see PayrollSettings::defaults()) are commonly-cited figures, NOT
 * guaranteed current — verify with TRA/an accountant before relying on
 * them for a real payroll run.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('payroll_settings', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->unique()->constrained()->cascadeOnDelete();
            $table->json('paye_brackets');
            $table->decimal('nssf_employee_percent', 5, 2)->default(10.00);
            $table->decimal('nssf_employer_percent', 5, 2)->default(10.00);
            $table->decimal('wcf_percent', 5, 2)->default(0.50);
            $table->decimal('sdl_percent', 5, 2)->default(3.50);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('payroll_settings');
    }
};

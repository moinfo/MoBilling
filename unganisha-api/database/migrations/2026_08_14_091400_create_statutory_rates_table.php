<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A tenant-configurable catalog of percent-of-gross statutory items
 * (NSSF, WCF, SDL, NHIF, or any other the tenant needs to add) — replaces
 * the fixed nssf_employee_percent/nssf_employer_percent/wcf_percent/
 * sdl_percent columns that used to live on payroll_settings, so adding a
 * new statutory scheme is a data change, not a code change. PAYE stays
 * separate (payroll_settings.paye_brackets) since it's bracket-based, not
 * a flat percentage, and every tenant has exactly one PAYE schedule.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('statutory_rates', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('name');
            $table->decimal('employee_percent', 5, 2)->default(0);
            $table->decimal('employer_percent', 5, 2)->default(0);
            // Whether the employee-side amount is deducted before PAYE is
            // calculated (like NSSF) or after (like most NHIF schemes).
            $table->boolean('reduces_taxable_income')->default(false);
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->index('tenant_id');
        });

        Schema::create('statutory_rate_subscriptions', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('user_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('statutory_rate_id')->constrained()->cascadeOnDelete();
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->unique(['user_id', 'statutory_rate_id']);
            $table->index('tenant_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('statutory_rate_subscriptions');
        Schema::dropIfExists('statutory_rates');
    }
};

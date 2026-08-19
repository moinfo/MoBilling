<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Non-statutory, individually-assigned deductions (HESLB, union dues,
 * etc). Statutory PAYE/NSSF/WCF/SDL are computed separately from
 * payroll_settings, not through this catalog — they have bracket/base
 * rules this simple fixed/percent shape can't express.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('deductions', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('name');
            $table->enum('calculation_type', ['fixed', 'percent_of_basic']);
            $table->decimal('default_amount', 12, 2)->default(0);
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->index('tenant_id');
        });

        Schema::create('deduction_subscriptions', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('user_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('deduction_id')->constrained()->cascadeOnDelete();
            $table->decimal('amount_override', 12, 2)->nullable();
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->unique(['user_id', 'deduction_id']);
            $table->index('tenant_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('deduction_subscriptions');
        Schema::dropIfExists('deductions');
    }
};

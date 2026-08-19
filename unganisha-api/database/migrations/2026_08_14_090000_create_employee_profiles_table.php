<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * HR Phase 1: structured employee-record data layered on top of the
 * existing `users` table (which only has auth/role/supervisor columns).
 * One profile per user. Deliberately excludes salary — that's a distinct
 * Payroll-phase concept (staff_salaries, not this table) to avoid an
 * awkward rename/migration once Payroll lands.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('employee_profiles', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('user_id')->unique()->constrained()->cascadeOnDelete();
            $table->string('employee_number')->nullable();
            $table->date('hire_date')->nullable();
            $table->string('department')->nullable();
            $table->string('position')->nullable();
            $table->enum('employment_type', ['full_time', 'part_time', 'contract', 'intern'])->nullable();
            $table->string('national_id')->nullable();
            $table->string('nssf_number')->nullable();
            $table->string('tin_number')->nullable();
            $table->date('date_of_birth')->nullable();
            $table->string('gender')->nullable();
            $table->string('next_of_kin_name')->nullable();
            $table->string('next_of_kin_phone')->nullable();
            $table->string('bank_name')->nullable();
            $table->string('bank_branch')->nullable();
            $table->string('bank_account_name')->nullable();
            $table->string('bank_account_number')->nullable();
            $table->string('mobile_money_provider')->nullable();
            $table->string('mobile_money_number')->nullable();
            $table->date('termination_date')->nullable();
            $table->text('notes')->nullable();
            $table->timestamps();

            $table->index('tenant_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('employee_profiles');
    }
};

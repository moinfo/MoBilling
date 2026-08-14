<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Immutable ledger (mirrors client_credits) — the audit trail for a
 * loan's balance. payroll_run_id is null for a manual/off-cycle payment
 * (e.g. an early payoff not tied to a payslip).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('loan_payments', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('loan_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('payroll_run_id')->nullable()->constrained()->nullOnDelete();
            $table->decimal('amount', 12, 2);
            $table->decimal('balance_after', 12, 2);
            $table->text('notes')->nullable();
            $table->foreignUuid('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->index(['tenant_id', 'loan_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('loan_payments');
    }
};

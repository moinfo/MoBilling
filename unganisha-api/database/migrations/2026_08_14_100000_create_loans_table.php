<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * balance is cached (mirrors clients.credit_balance) and only ever
 * mutated by LoanService inside a locked transaction, alongside a
 * loan_payments ledger row — never decremented directly.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('loans', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('user_id')->constrained()->cascadeOnDelete();
            $table->decimal('principal', 12, 2);
            $table->decimal('balance', 12, 2);
            $table->decimal('monthly_installment', 12, 2);
            $table->date('issued_date');
            $table->enum('status', ['active', 'paid_off', 'cancelled'])->default('active');
            $table->text('notes')->nullable();
            $table->foreignUuid('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->index(['tenant_id', 'user_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('loans');
    }
};

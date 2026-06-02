<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('petty_cash_transactions', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('petty_cash_account_id')->constrained('petty_cash_accounts')->cascadeOnDelete();
            $table->foreignUuid('created_by')->nullable()->constrained('users')->nullOnDelete();

            // top_up        = float allocation (money in)
            // return        = excess cash returned to source (money out)
            // adjustment_in/out = corrections emitted by a reconciliation
            $table->enum('type', ['top_up', 'return', 'adjustment_in', 'adjustment_out']);
            $table->decimal('amount', 12, 2);
            $table->date('transaction_date');

            // Adjustments are linked back to the reconciliation that produced them
            $table->foreignUuid('reconciliation_id')->nullable()
                ->constrained('petty_cash_reconciliations')->nullOnDelete();

            $table->string('reference')->nullable();
            $table->text('notes')->nullable();
            $table->timestamps();
            $table->softDeletes();

            $table->index(['tenant_id', 'transaction_date']);
            $table->index(['petty_cash_account_id', 'type']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('petty_cash_transactions');
    }
};

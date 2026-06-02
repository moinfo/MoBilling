<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('petty_cash_reconciliations', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('petty_cash_account_id')->constrained('petty_cash_accounts')->cascadeOnDelete();
            $table->foreignUuid('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->dateTime('reconciled_at');
            $table->decimal('ledger_balance', 12, 2);   // system-computed at count time
            $table->decimal('counted_balance', 12, 2);  // what the custodian physically counted
            $table->decimal('difference', 12, 2);       // counted - ledger (signed)
            $table->enum('resolution', ['accepted', 'investigating'])->default('investigating');
            $table->text('notes')->nullable();
            $table->timestamps();

            $table->index(['tenant_id', 'reconciled_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('petty_cash_reconciliations');
    }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A white-label reseller tenant's prepaid wallet ledger — mirrors
 * client_credits (CreditService) one level up: tenants.wallet_balance is
 * the cached authoritative balance, this table is the audit trail. Every
 * row is a topup (Pesapal or staff-confirmed "paid outside"), a debit
 * (auto-charged at cost when the reseller's own client fulfillment runs),
 * or a refund. related_type/related_id trace a debit back to whatever it
 * paid for (a ClientSubscription or Domain of the reseller tenant).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('tenant_wallet_transactions', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->enum('type', ['topup', 'debit', 'refund'])->default('topup');
            $table->decimal('amount', 14, 2); // positive for topup/refund, negative for debit
            $table->decimal('balance_after', 14, 2);
            $table->string('reference')->nullable();
            $table->string('related_type')->nullable();
            $table->uuid('related_id')->nullable();
            $table->foreignUuid('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->text('notes')->nullable();
            $table->dateTime('created_at')->nullable();
            $table->dateTime('updated_at')->nullable();

            $table->index(['tenant_id', 'created_at']);
            $table->index(['related_type', 'related_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('tenant_wallet_transactions');
    }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Refunds: money already paid on an invoice returned to the client — either
     * back to the account credit wallet (method 'wallet') or externally via
     * cash/bank/mobile money (recorded for the audit trail only). A refund nets
     * down the invoice's paid_amount (see Document::getPaidAmountAttribute).
     */
    public function up(): void
    {
        Schema::create('refunds', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('document_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('client_id')->constrained()->cascadeOnDelete();
            $table->decimal('amount', 15, 2);
            $table->enum('method', ['wallet', 'cash', 'bank', 'mpesa', 'pesapal', 'other']);
            $table->string('reference')->nullable();
            $table->text('notes')->nullable();
            $table->foreignUuid('refunded_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();
            $table->index(['document_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('refunds');
    }
};

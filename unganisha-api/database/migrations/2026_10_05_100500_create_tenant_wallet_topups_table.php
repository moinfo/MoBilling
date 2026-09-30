<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A reseller tenant's self-service Pesapal wallet top-up request — mirrors
 * wifi_voucher_purchases/sms_purchases: paid via the TENANT'S OWN Pesapal
 * account (TenantPesapalService), never Moinfotech's. On completion (IPN,
 * verified via TenantPesapalWebhookController) TenantWalletService::topUp()
 * credits the wallet. Staff-confirmed "paid outside" top-ups go straight
 * into tenant_wallet_transactions and never create a row here.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('tenant_wallet_topups', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('requested_by')->nullable()->constrained('users')->nullOnDelete();
            $table->decimal('amount', 14, 2);
            $table->enum('status', ['pending', 'completed', 'failed'])->default('pending');

            $table->string('order_tracking_id')->nullable();
            $table->text('pesapal_redirect_url')->nullable();
            $table->string('payment_status_description')->nullable();
            $table->string('confirmation_code')->nullable();
            $table->string('payment_method_used')->nullable();
            $table->json('gateway_response')->nullable();
            $table->dateTime('completed_at')->nullable();

            $table->dateTime('created_at')->nullable();
            $table->dateTime('updated_at')->nullable();

            $table->index('order_tracking_id');
            $table->index(['tenant_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('tenant_wallet_topups');
    }
};

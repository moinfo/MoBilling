<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * A walk-in WiFi voucher sale — mirrors license_purchases: an
     * anonymous buyer identified only by phone, no Client/Document/Invoice
     * involved. Paid via the owning tenant's own Pesapal account
     * (TenantPesapalService), same fields as tenant_subscriptions/
     * pesapal_invoice_payments for the payment leg.
     */
    public function up(): void
    {
        Schema::create('wifi_voucher_purchases', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('mikrotik_router_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('wifi_plan_id')->constrained()->cascadeOnDelete();
            $table->string('customer_phone');
            $table->string('customer_name')->nullable();
            $table->decimal('amount', 12, 2);
            $table->enum('status', ['pending', 'completed', 'failed'])->default('pending');

            // Pesapal payment fields — mirrors license_purchases/tenant_subscriptions
            $table->string('order_tracking_id')->nullable();
            $table->text('pesapal_redirect_url')->nullable();
            $table->string('payment_status_description')->nullable();
            $table->string('confirmation_code')->nullable();
            $table->string('payment_method_used')->nullable();
            $table->json('gateway_response')->nullable();
            $table->timestamp('completed_at')->nullable();

            // Voucher credential handed to the customer — short-lived, low
            // value (like a printed scratch-card code), plain column.
            $table->string('hotspot_username')->nullable();
            $table->string('hotspot_password')->nullable();
            $table->timestamp('voucher_expires_at')->nullable();

            $table->json('meta')->nullable();
            $table->timestamps();

            $table->index('order_tracking_id');
            $table->index(['tenant_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('wifi_voucher_purchases');
    }
};

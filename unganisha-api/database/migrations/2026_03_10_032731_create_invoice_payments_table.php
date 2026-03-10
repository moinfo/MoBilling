<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('pesapal_invoice_payments', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('tenant_id');
            $table->uuid('document_id');
            $table->string('merchant_reference')->unique();
            $table->string('order_tracking_id')->nullable();
            $table->string('pesapal_redirect_url', 2048)->nullable();
            $table->decimal('amount', 14, 2);
            $table->string('currency', 10)->default('TZS');
            $table->string('status')->default('pending'); // pending, completed, failed
            $table->string('payment_status_description')->nullable();
            $table->string('payment_method_used')->nullable();
            $table->string('confirmation_code')->nullable();
            $table->json('gateway_response')->nullable();
            $table->timestamp('completed_at')->nullable();
            $table->timestamps();

            $table->foreign('tenant_id')->references('id')->on('tenants')->cascadeOnDelete();
            $table->foreign('document_id')->references('id')->on('documents')->cascadeOnDelete();
            $table->index('order_tracking_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('pesapal_invoice_payments');
    }
};

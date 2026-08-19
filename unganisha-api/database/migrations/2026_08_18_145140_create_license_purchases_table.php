<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('license_purchases', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('customer_name');
            $table->string('customer_email');
            $table->string('customer_phone')->nullable();
            $table->string('product');
            $table->string('billing_period');
            $table->decimal('amount', 12, 2);
            $table->enum('status', ['pending', 'completed', 'failed'])->default('pending');
            $table->foreignUuid('license_id')->nullable()->constrained()->nullOnDelete();

            // Pesapal payment fields — mirrors tenant_subscriptions
            $table->string('order_tracking_id')->nullable();
            $table->text('pesapal_redirect_url')->nullable();
            $table->string('payment_status_description')->nullable();
            $table->string('confirmation_code')->nullable();
            $table->string('payment_method_used')->nullable();
            $table->json('gateway_response')->nullable();
            $table->timestamp('completed_at')->nullable();

            $table->timestamps();

            $table->index('order_tracking_id');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('license_purchases');
    }
};

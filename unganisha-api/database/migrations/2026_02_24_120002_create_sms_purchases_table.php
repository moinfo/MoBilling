<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('sms_purchases', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('user_id')->constrained()->cascadeOnDelete();
            $table->unsignedInteger('sms_quantity');
            $table->decimal('price_per_sms', 8, 2);
            $table->decimal('total_amount', 12, 2);
            $table->string('package_name', 50);
            $table->enum('status', ['pending', 'completed', 'failed'])->default('pending');
            $table->string('order_tracking_id')->nullable();
            $table->text('pesapal_redirect_url')->nullable();
            $table->string('payment_status_description')->nullable();
            $table->string('confirmation_code')->nullable();
            $table->string('payment_method_used')->nullable();
            $table->json('gateway_response')->nullable();
            $table->timestamp('completed_at')->nullable();
            $table->timestamps();

            $table->index('order_tracking_id');
            $table->index(['tenant_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('sms_purchases');
    }
};

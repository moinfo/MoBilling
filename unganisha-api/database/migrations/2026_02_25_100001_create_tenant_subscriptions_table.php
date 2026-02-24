<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('tenant_subscriptions', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('subscription_plan_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('user_id')->nullable()->constrained()->nullOnDelete();
            $table->enum('status', ['pending', 'active', 'expired', 'cancelled'])->default('pending');
            $table->timestamp('starts_at')->nullable();
            $table->timestamp('ends_at')->nullable();
            $table->decimal('amount_paid', 12, 2)->default(0);

            // Pesapal payment fields
            $table->string('order_tracking_id')->nullable();
            $table->text('pesapal_redirect_url')->nullable();
            $table->string('payment_status_description')->nullable();
            $table->string('confirmation_code')->nullable();
            $table->string('payment_method_used')->nullable();
            $table->json('gateway_response')->nullable();
            $table->timestamp('paid_at')->nullable();

            $table->timestamps();

            $table->index('order_tracking_id');
            $table->index(['tenant_id', 'status']);
            $table->index(['tenant_id', 'ends_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('tenant_subscriptions');
    }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Audit + per-client usage of coupons. One row per applied redemption
     * (order or, for recurring coupons, each discounted renewal).
     */
    public function up(): void
    {
        Schema::create('coupon_redemptions', function (Blueprint $t) {
            $t->uuid('id')->primary();
            $t->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $t->foreignUuid('coupon_id')->constrained()->cascadeOnDelete();
            $t->foreignUuid('client_id')->constrained()->cascadeOnDelete();
            $t->foreignUuid('document_id')->nullable()->constrained()->nullOnDelete();
            $t->decimal('discount_amount', 15, 2)->default(0);
            $t->timestamps();

            $t->index(['tenant_id', 'coupon_id']);
            $t->index(['tenant_id', 'client_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('coupon_redemptions');
    }
};

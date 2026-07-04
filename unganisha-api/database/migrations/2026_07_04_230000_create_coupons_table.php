<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Promotions / coupon codes (WHMCS-parity). Tenant-defined discount codes
     * applied at order time. Discount is always computed server-side from these
     * rows — a client-sent discount is never trusted.
     */
    public function up(): void
    {
        Schema::create('coupons', function (Blueprint $t) {
            $t->uuid('id')->primary();
            $t->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $t->string('code'); // stored UPPER-cased
            $t->string('description')->nullable();
            $t->enum('type', ['percent', 'fixed'])->default('percent');
            $t->decimal('value', 15, 2)->default(0);
            $t->enum('applies_to', ['all', 'product'])->default('all');
            $t->unsignedInteger('max_uses')->nullable(); // null = unlimited
            $t->unsignedInteger('uses')->default(0);
            $t->decimal('min_order', 15, 2)->nullable();
            $t->dateTime('starts_at')->nullable();
            $t->dateTime('expires_at')->nullable();
            $t->boolean('recurring')->default(false);
            $t->boolean('is_active')->default(true);
            $t->timestamps();
            $t->softDeletes();

            $t->unique(['tenant_id', 'code']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('coupons');
    }
};

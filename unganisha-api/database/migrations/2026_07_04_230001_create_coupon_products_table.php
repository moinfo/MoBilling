<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Pivot: when a coupon's applies_to = product, it only discounts these
     * products. Composite keyless PK mirrors product_addon_links.
     */
    public function up(): void
    {
        Schema::create('coupon_products', function (Blueprint $t) {
            $t->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $t->foreignUuid('coupon_id')->constrained()->cascadeOnDelete();
            $t->foreignUuid('product_service_id')->constrained()->cascadeOnDelete();

            $t->primary(['coupon_id', 'product_service_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('coupon_products');
    }
};

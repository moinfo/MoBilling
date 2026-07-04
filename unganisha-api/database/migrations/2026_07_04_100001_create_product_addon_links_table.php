<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Pivot: which products offer which add-ons.
     */
    public function up(): void
    {
        Schema::create('product_addon_links', function (Blueprint $t) {
            $t->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $t->foreignUuid('product_addon_id')->constrained()->cascadeOnDelete();
            $t->foreignUuid('product_service_id')->constrained()->cascadeOnDelete();

            $t->primary(['product_addon_id', 'product_service_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('product_addon_links');
    }
};

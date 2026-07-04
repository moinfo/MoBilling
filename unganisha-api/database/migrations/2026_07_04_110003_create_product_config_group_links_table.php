<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Pivot: which products offer which configurable option groups.
     */
    public function up(): void
    {
        Schema::create('product_config_group_links', function (Blueprint $t) {
            $t->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $t->foreignUuid('config_option_group_id')->constrained()->cascadeOnDelete();
            $t->foreignUuid('product_service_id')->constrained()->cascadeOnDelete();

            $t->primary(['config_option_group_id', 'product_service_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('product_config_group_links');
    }
};

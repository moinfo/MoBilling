<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * A single option within a group. dropdown/radio options carry selectable
     * choices (with their own prices); quantity/yesno options carry a single
     * unit_price and no choices.
     */
    public function up(): void
    {
        Schema::create('config_options', function (Blueprint $t) {
            $t->uuid('id')->primary();
            $t->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $t->foreignUuid('config_option_group_id')->constrained()->cascadeOnDelete();
            $t->string('name');
            $t->enum('option_type', ['dropdown', 'radio', 'yesno', 'quantity'])->default('dropdown');
            $t->decimal('unit_price', 15, 2)->nullable(); // quantity/yesno only
            $t->integer('sort_order')->default(0);
            $t->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('config_options');
    }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Selectable values for a dropdown/radio option (e.g. RAM: 2GB=+0,
     * 4GB=+10000, 8GB=+25000). Each choice carries its own price.
     */
    public function up(): void
    {
        Schema::create('config_option_choices', function (Blueprint $t) {
            $t->uuid('id')->primary();
            $t->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $t->foreignUuid('config_option_id')->constrained()->cascadeOnDelete();
            $t->string('label');
            $t->decimal('price', 15, 2)->default(0);
            $t->integer('sort_order')->default(0);
            $t->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('config_option_choices');
    }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('product_services', function (Blueprint $table) {
            $table->string('unit', 20)->nullable()->default('pcs')->change();
        });
    }

    public function down(): void
    {
        Schema::table('product_services', function (Blueprint $table) {
            $table->string('unit', 20)->nullable(false)->default('pcs')->change();
        });
    }
};

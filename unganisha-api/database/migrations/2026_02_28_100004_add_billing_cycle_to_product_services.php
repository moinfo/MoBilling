<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('product_services', function (Blueprint $table) {
            $table->enum('billing_cycle', ['once', 'monthly', 'quarterly', 'half_yearly', 'yearly'])
                ->nullable()
                ->after('category');
        });
    }

    public function down(): void
    {
        Schema::table('product_services', function (Blueprint $table) {
            $table->dropColumn('billing_cycle');
        });
    }
};

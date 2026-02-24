<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('document_items', function (Blueprint $table) {
            $table->decimal('discount_percent', 5, 2)->default(0)->after('price');
        });

        Schema::table('documents', function (Blueprint $table) {
            $table->decimal('discount_amount', 12, 2)->default(0)->after('subtotal');
        });
    }

    public function down(): void
    {
        Schema::table('document_items', function (Blueprint $table) {
            $table->dropColumn('discount_percent');
        });

        Schema::table('documents', function (Blueprint $table) {
            $table->dropColumn('discount_amount');
        });
    }
};

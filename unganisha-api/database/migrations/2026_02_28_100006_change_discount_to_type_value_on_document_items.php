<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('document_items', function (Blueprint $table) {
            $table->renameColumn('discount_percent', 'discount_value');
        });

        Schema::table('document_items', function (Blueprint $table) {
            $table->enum('discount_type', ['percent', 'flat'])->default('percent')->after('price');
        });
    }

    public function down(): void
    {
        Schema::table('document_items', function (Blueprint $table) {
            $table->dropColumn('discount_type');
        });

        Schema::table('document_items', function (Blueprint $table) {
            $table->renameColumn('discount_value', 'discount_percent');
        });
    }
};

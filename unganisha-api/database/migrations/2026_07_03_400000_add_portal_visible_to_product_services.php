<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /** Controls whether a product appears in the client-portal shopping catalog. */
    public function up(): void
    {
        Schema::table('product_services', function (Blueprint $t) {
            $t->boolean('portal_visible')->default(true);
        });
    }

    public function down(): void
    {
        Schema::table('product_services', function (Blueprint $t) {
            $t->dropColumn('portal_visible');
        });
    }
};

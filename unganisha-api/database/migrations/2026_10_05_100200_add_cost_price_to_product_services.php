<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Wholesale cost basis for a product — used only by the reseller-tenant
 * wallet gate (TenantWalletGateService) to compute how much a fulfillment
 * debits from the reseller's wallet. Null means "no real cost source known"
 * — the gate treats that as blocking, never as free.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('product_services', function (Blueprint $table) {
            $table->decimal('cost_price', 12, 2)->nullable()->after('price');
        });
    }

    public function down(): void
    {
        Schema::table('product_services', function (Blueprint $table) {
            $table->dropColumn('cost_price');
        });
    }
};

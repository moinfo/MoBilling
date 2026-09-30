<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * A product/service row duplicated onto a wallet-gated reseller tenant at
     * provisioning (ResellerProvisioningService::duplicateProducts()) is real
     * shared infrastructure (a server + cPanel package the reseller must
     * never reconfigure) — they may adjust its price (directly, or via the
     * "set your margin" bulk tool), but editing any other field or deleting
     * it outright is staff-only. A product the reseller creates themselves
     * afterward is fully theirs to manage — this flag is what tells the two
     * apart.
     */
    public function up(): void
    {
        Schema::table('product_services', function (Blueprint $table) {
            $table->boolean('managed_by_platform')->default(false)->after('cost_price');
        });
    }

    public function down(): void
    {
        Schema::table('product_services', function (Blueprint $table) {
            $table->dropColumn('managed_by_platform');
        });
    }
};

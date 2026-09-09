<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * self_managed  = the tenant's own Pesapal account collects the money
     *                 directly (v1 default — unchanged behavior).
     * platform_collected = MoBilling's own Pesapal account collects it;
     *                 the tenant is owed a payout, tracked and manually
     *                 settled via the superadmin WiFi Settlements ledger.
     */
    public function up(): void
    {
        Schema::table('mikrotik_routers', function (Blueprint $table) {
            $table->enum('payment_mode', ['self_managed', 'platform_collected'])
                ->default('self_managed')->after('use_tls');
        });
    }

    public function down(): void
    {
        Schema::table('mikrotik_routers', function (Blueprint $table) {
            $table->dropColumn('payment_mode');
        });
    }
};

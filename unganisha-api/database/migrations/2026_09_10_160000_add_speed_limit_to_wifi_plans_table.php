<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Mbps, symmetric (same up/down) — null = unlimited. Mainly a
        // sharing deterrent: if someone tethers this voucher to several
        // people, everyone splits a capped pipe and it gets slow fast.
        Schema::table('wifi_plans', function (Blueprint $table) {
            $table->decimal('speed_limit_mbps', 6, 2)->nullable()->after('data_cap_mb');
        });
    }

    public function down(): void
    {
        Schema::table('wifi_plans', function (Blueprint $table) {
            $table->dropColumn('speed_limit_mbps');
        });
    }
};

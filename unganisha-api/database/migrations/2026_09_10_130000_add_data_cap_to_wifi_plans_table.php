<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Nullable = unlimited data (current behavior, time-limited only).
        // Set alongside duration_value/duration_unit to sell "2GB, valid 1
        // day" style plans — RouterOS ends the session on whichever limit
        // is hit first (see RouterOsService::createHotspotUser's
        // limit-bytes-total).
        Schema::table('wifi_plans', function (Blueprint $table) {
            $table->unsignedBigInteger('data_cap_mb')->nullable()->after('duration_unit');
        });
    }

    public function down(): void
    {
        Schema::table('wifi_plans', function (Blueprint $table) {
            $table->dropColumn('data_cap_mb');
        });
    }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // The LAN-side address the hotspot serves its login page on (e.g.
        // "192.168.88.1"), as seen by devices connected to the WiFi — this
        // is distinct from `host`, which is the WAN/tunnel address MoBilling
        // uses server-side to reach the router's API. Needed to auto-login
        // a customer's own device straight into the hotspot after payment,
        // by sending their browser to http://{local_login_host}/login.
        Schema::table('mikrotik_routers', function (Blueprint $table) {
            $table->string('local_login_host')->nullable()->after('host');
        });
    }

    public function down(): void
    {
        Schema::table('mikrotik_routers', function (Blueprint $table) {
            $table->dropColumn('local_login_host');
        });
    }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Lets a self-hosted install's own scheduled license:check command
 * re-validate against the hosted license server without needing to
 * re-parse storage/app/installed.lock — the key it was activated with,
 * and the last time that check actually succeeded (used for the grace
 * period so a transient network outage never locks a customer out).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->string('license_key')->nullable()->after('is_self_hosted');
            $table->timestamp('license_last_valid_at')->nullable()->after('license_key');
        });
    }

    public function down(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->dropColumn(['license_key', 'license_last_valid_at']);
        });
    }
};

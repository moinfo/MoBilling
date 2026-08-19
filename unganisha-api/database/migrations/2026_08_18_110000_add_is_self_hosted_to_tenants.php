<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A self-hosted install has no MoBilling-billed trial/subscription — access
 * is gated by its License instead (checked by the install's own license
 * server, not by TenantSubscription). Tenant::hasAccess() needs a way to
 * grant access to a self-hosted tenant without a fake trial/subscription
 * row. Defaults false, so every existing SaaS tenant is unaffected.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->boolean('is_self_hosted')->default(false)->after('is_active');
        });
    }

    public function down(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->dropColumn('is_self_hosted');
        });
    }
};

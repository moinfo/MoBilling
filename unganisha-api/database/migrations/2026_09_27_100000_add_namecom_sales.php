<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/** Name.com TLD catalog/pricing + per-tenant pricing/auto-register settings. Additive only. */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('domain_tlds', function (Blueprint $t) {
            $t->string('registrar', 20)->default('fred')->after('tld');       // fred | namecom
            $t->decimal('usd_register', 10, 2)->nullable();
            $t->decimal('usd_renew', 10, 2)->nullable();
            $t->decimal('usd_transfer', 10, 2)->nullable();
            $t->boolean('price_overridden')->default(false);
            $t->boolean('usd_changed')->default(false);
            $t->json('usd_prev')->nullable();
            $t->timestamp('usd_synced_at')->nullable();
            $t->index(['tenant_id', 'registrar']);
        });

        Schema::create('namecom_settings', function (Blueprint $t) {
            $t->uuid('id')->primary();
            $t->uuid('tenant_id')->unique();
            $t->decimal('usd_rate', 12, 4)->default(3000);
            $t->decimal('fixed_markup', 12, 2)->default(10000);
            $t->boolean('auto_register')->default(false);
            $t->decimal('auto_cap_usd', 8, 2)->default(50);
            $t->unsignedSmallInteger('auto_daily_limit')->default(10);
            $t->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('namecom_settings');
        Schema::table('domain_tlds', function (Blueprint $t) {
            $t->dropIndex(['tenant_id', 'registrar']);
            $t->dropColumn(['registrar', 'usd_register', 'usd_renew', 'usd_transfer', 'price_overridden', 'usd_changed', 'usd_prev', 'usd_synced_at']);
        });
    }
};

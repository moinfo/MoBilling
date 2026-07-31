<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Master switch for automatic suspension of unpaid subscriptions — sometimes a
 * tenant wants dunning notices only, with suspension done manually.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->boolean('auto_suspend_enabled')->default(true)->after('subscription_grace_days');
        });
    }

    public function down(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->dropColumn('auto_suspend_enabled');
        });
    }
};

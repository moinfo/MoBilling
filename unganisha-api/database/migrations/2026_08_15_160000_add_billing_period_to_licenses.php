<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Licenses are sold as subscriptions (WHMCS-style) — expires_at should be
 * calculated from a start date + billing period, not hand-picked. Keeps
 * starts_at/billing_period on record so the calculation is reproducible
 * (e.g. for a future renewal action) rather than only storing the result.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('licenses', function (Blueprint $table) {
            $table->enum('billing_period', ['perpetual', 'monthly', 'quarterly', 'semi_annual', 'annual'])
                ->default('perpetual')->after('domain');
            $table->date('starts_at')->nullable()->after('billing_period');
        });
    }

    public function down(): void
    {
        Schema::table('licenses', function (Blueprint $table) {
            $table->dropColumn(['billing_period', 'starts_at']);
        });
    }
};

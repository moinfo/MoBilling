<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Employee of the Month voting is opt-in per tenant — defaults off so it
 * doesn't surprise every reseller/client tenant on the platform the moment
 * it ships; a tenant admin turns it on for their own staff from the
 * Payroll > Settings tab.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('payroll_settings', function (Blueprint $table) {
            $table->boolean('eotm_enabled')->default(false)->after('paye_brackets');
        });
    }

    public function down(): void
    {
        Schema::table('payroll_settings', function (Blueprint $table) {
            $table->dropColumn('eotm_enabled');
        });
    }
};

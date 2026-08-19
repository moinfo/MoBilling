<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Each statutory body identifies an employee by its own number (NSSF
 * number, HESLB registration number, NHIF membership number, ...). PAYE's
 * TIN and the legacy NSSF number already live on employee_profiles and
 * stay there; this is for anything a tenant adds to the statutory_rates
 * catalog going forward, so a new catalog item automatically gets a
 * per-employee reference field without another migration.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('statutory_rate_subscriptions', function (Blueprint $table) {
            $table->string('reference_number')->nullable()->after('is_active');
        });
    }

    public function down(): void
    {
        Schema::table('statutory_rate_subscriptions', function (Blueprint $table) {
            $table->dropColumn('reference_number');
        });
    }
};

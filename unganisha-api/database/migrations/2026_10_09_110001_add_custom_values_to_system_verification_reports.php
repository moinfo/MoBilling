<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Values for admin-defined custom fields (system_verification_field_definitions),
 * keyed by their `key`. The four built-in figures (cash, sales, credit,
 * gain_loss) keep their own typed decimal columns, unaffected — this is only
 * for whatever an admin adds beyond those.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('system_verification_reports', function (Blueprint $table) {
            $table->json('custom_values')->nullable()->after('gain_loss');
        });
    }

    public function down(): void
    {
        Schema::table('system_verification_reports', function (Blueprint $table) {
            $table->dropColumn('custom_values');
        });
    }
};

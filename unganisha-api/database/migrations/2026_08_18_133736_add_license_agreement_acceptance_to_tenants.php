<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->string('license_agreement_version')->nullable()->after('license_expires_at');
            $table->timestamp('license_agreement_accepted_at')->nullable()->after('license_agreement_version');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->dropColumn(['license_agreement_version', 'license_agreement_accepted_at']);
        });
    }
};

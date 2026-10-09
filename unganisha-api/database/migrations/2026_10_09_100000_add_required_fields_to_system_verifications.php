<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Which of the daily closing figures (cash, sales, credit, gain_loss — see
 * SystemVerification::AVAILABLE_FIELDS) apply to a given system. Null means
 * "all of them" (the original, pre-this-column behavior) so existing rows
 * keep working unchanged — see SystemVerification::requiredFields().
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('system_verifications', function (Blueprint $table) {
            $table->json('required_fields')->nullable()->after('window_to');
        });
    }

    public function down(): void
    {
        Schema::table('system_verifications', function (Blueprint $table) {
            $table->dropColumn('required_fields');
        });
    }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The check-in window isn't one rule for the whole tenant — different
 * assigned staff (and different systems) close out at different times, so
 * each needs its own window. Moves window_from/window_to off tenants and
 * onto system_verifications, where assigned_user_id already lives.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->dropColumn(['system_verification_window_from', 'system_verification_window_to']);
        });

        Schema::table('system_verifications', function (Blueprint $table) {
            $table->time('window_from')->nullable()->after('login_password');
            $table->time('window_to')->nullable()->after('window_from');
        });
    }

    public function down(): void
    {
        Schema::table('system_verifications', function (Blueprint $table) {
            $table->dropColumn(['window_from', 'window_to']);
        });

        Schema::table('tenants', function (Blueprint $table) {
            $table->time('system_verification_window_from')->nullable()->after('is_wallet_gated');
            $table->time('system_verification_window_to')->nullable()->after('system_verification_window_from');
        });
    }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The daily window within which staff are expected to do their system
 * verification check-ins (e.g. 18:00-20:00, after the client's business
 * closes for the day). Tenant-wide, not per-system — it's a schedule rule,
 * not a property of any one system. Nullable: unset means no window is
 * enforced (today's behavior, unchanged), matching how attendance_settings'
 * exception window started nullable too.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->time('system_verification_window_from')->nullable()->after('is_wallet_gated');
            $table->time('system_verification_window_to')->nullable()->after('system_verification_window_from');
        });
    }

    public function down(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->dropColumn(['system_verification_window_from', 'system_verification_window_to']);
        });
    }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Forgot-password OTP was hard-gated on having an email address, even though
 * the SMS/WhatsApp send logic already existed — a phone-only client could
 * never even request a code. This makes the OTP record identifier-keyed
 * (email OR normalized phone) and allows portal accounts without an email.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('portal_otps', function (Blueprint $table) {
            $table->string('identifier')->nullable()->after('email');
        });
        DB::table('portal_otps')->whereNull('identifier')->update(['identifier' => DB::raw('email')]);

        Schema::table('client_users', function (Blueprint $table) {
            $table->string('email')->nullable()->change();
        });
    }

    public function down(): void
    {
        Schema::table('client_users', function (Blueprint $table) {
            $table->string('email')->nullable(false)->change();
        });
        Schema::table('portal_otps', function (Blueprint $table) {
            $table->dropColumn('identifier');
        });
    }
};

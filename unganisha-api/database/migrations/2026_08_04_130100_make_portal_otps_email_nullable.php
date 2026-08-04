<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Follow-up to 2026_08_04_130000: portal_otps.email was still NOT NULL,
 * which broke OTP inserts for phone-only accounts (no email to store).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('portal_otps', function (Blueprint $table) {
            $table->string('email')->nullable()->change();
        });
    }

    public function down(): void
    {
        Schema::table('portal_otps', function (Blueprint $table) {
            $table->string('email')->nullable(false)->change();
        });
    }
};

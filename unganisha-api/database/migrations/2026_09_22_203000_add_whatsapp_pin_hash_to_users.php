<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A short PIN gating "staff assist" mode over WhatsApp — a staff member using their own
 * phone to act on behalf of a client they're helping. Phone-number match against User.phone
 * alone has no second factor (same gap fixed for MoSMS's own self-service).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->string('whatsapp_pin_hash')->nullable()->after('phone');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('whatsapp_pin_hash');
        });
    }
};

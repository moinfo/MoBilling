<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * When set, this session is a staff member (their own phone, PIN-verified) acting on behalf
 * of client_id, not the client's own self-service session — every reply gets an "assisted by"
 * banner, and order/document records get tagged with who really acted, for accountability.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('whatsapp_renewal_sessions', function (Blueprint $table) {
            $table->foreignUuid('assisted_by_user_id')->nullable()->after('client_id')
                ->constrained('users')->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('whatsapp_renewal_sessions', function (Blueprint $table) {
            $table->dropConstrainedForeignId('assisted_by_user_id');
        });
    }
};

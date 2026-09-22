<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Bounds how many times a phone can guess the surname during identity
 * verification before the session is dropped — a phone match alone isn't
 * proof of identity, but unlimited guesses would defeat the point of asking.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('whatsapp_renewal_sessions', function (Blueprint $table) {
            $table->unsignedTinyInteger('attempts')->default(0)->after('confirmed_at');
        });
    }

    public function down(): void
    {
        Schema::table('whatsapp_renewal_sessions', function (Blueprint $table) {
            $table->dropColumn('attempts');
        });
    }
};

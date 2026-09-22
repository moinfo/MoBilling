<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A phone that doesn't match any existing Client now gets a self-registration
 * conversation instead of silence — that session exists before any Client
 * row does, so client_id can no longer be required.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('whatsapp_renewal_sessions', function (Blueprint $table) {
            $table->dropForeign(['client_id']);
        });
        Schema::table('whatsapp_renewal_sessions', function (Blueprint $table) {
            $table->foreignUuid('client_id')->nullable()->change();
            $table->foreign('client_id')->references('id')->on('clients')->cascadeOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('whatsapp_renewal_sessions', function (Blueprint $table) {
            $table->dropForeign(['client_id']);
        });
        Schema::table('whatsapp_renewal_sessions', function (Blueprint $table) {
            $table->foreignUuid('client_id')->nullable(false)->change();
            $table->foreign('client_id')->references('id')->on('clients')->cascadeOnDelete();
        });
    }
};

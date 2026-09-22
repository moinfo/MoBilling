<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Turns the single-purpose renewal-reply session into a small step-machine
 * so the same WhatsApp conversation can also walk a client through ordering
 * a brand-new domain or hosting plan. `flow` null keeps today's root-menu/
 * renewal-picker behavior; `state` carries whatever the current step needs
 * to remember (typed domain name, chosen plan, price shown, etc.).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('whatsapp_renewal_sessions', function (Blueprint $table) {
            $table->string('flow')->nullable()->after('client_id');
            $table->json('state')->nullable()->after('flow');
        });
    }

    public function down(): void
    {
        Schema::table('whatsapp_renewal_sessions', function (Blueprint $table) {
            $table->dropColumn(['flow', 'state']);
        });
    }
};

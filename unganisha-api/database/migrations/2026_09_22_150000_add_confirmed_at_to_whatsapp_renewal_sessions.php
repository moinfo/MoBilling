<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The WhatsApp self-service catch-all must not show a matched account's
 * services on the strength of a phone-number match alone — a stranger's
 * message could get routed to the wrong account by the "most recent
 * sender" heuristic MoSMS uses on its shared number. Null = we've asked
 * "is this your account?" and are waiting for a yes; set = confirmed, and
 * `items` is now the menu they're picking from.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('whatsapp_renewal_sessions', function (Blueprint $table) {
            $table->timestamp('confirmed_at')->nullable()->after('items');
        });
    }

    public function down(): void
    {
        Schema::table('whatsapp_renewal_sessions', function (Blueprint $table) {
            $table->dropColumn('confirmed_at');
        });
    }
};

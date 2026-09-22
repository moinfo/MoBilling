<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Generalizes the single-domain reminder-reply session into a numbered menu
 * session — a client can now be shown several billable domains at once (the
 * WhatsApp self-service "what can I do" catch-all) and pick one by number,
 * not just confirm the one domain a specific reminder was about. Both cases
 * now share the same `items` ordered list (the reminder-reply path just
 * always writes a single-element list).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('whatsapp_renewal_sessions', function (Blueprint $table) {
            $table->dropForeign(['domain_id']);
            $table->dropColumn('domain_id');
            $table->json('items')->nullable()->after('client_id');
        });
    }

    public function down(): void
    {
        Schema::table('whatsapp_renewal_sessions', function (Blueprint $table) {
            $table->dropColumn('items');
            $table->foreignUuid('domain_id')->nullable()->after('client_id')->constrained()->cascadeOnDelete();
        });
    }
};

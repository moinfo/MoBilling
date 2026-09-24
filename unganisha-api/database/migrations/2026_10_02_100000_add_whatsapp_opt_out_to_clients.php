<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A client who texts STOP to the WhatsApp bot stops receiving WhatsApp reminders/notifications
 * (email etc. unaffected). START re-enables. Additive, nullable.
 */
return new class extends Migration {
    public function up(): void
    {
        if (!Schema::hasColumn('clients', 'whatsapp_opt_out_at')) {
            Schema::table('clients', function (Blueprint $table) {
                $table->dateTime('whatsapp_opt_out_at')->nullable();
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasColumn('clients', 'whatsapp_opt_out_at')) {
            Schema::table('clients', function (Blueprint $table) {
                $table->dropColumn('whatsapp_opt_out_at');
            });
        }
    }
};

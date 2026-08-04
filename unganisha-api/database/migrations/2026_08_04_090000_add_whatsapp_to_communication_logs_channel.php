<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * WhatsApp sends were silently failing to log (and, worse, throwing back
 * through notifyNow() and making the whole send look like it failed) because
 * `channel` was a strict enum('email','sms') — WhatsApp was never a member.
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::statement("ALTER TABLE communication_logs MODIFY channel ENUM('email','sms','whatsapp') NOT NULL");
    }

    public function down(): void
    {
        DB::statement("ALTER TABLE communication_logs MODIFY channel ENUM('email','sms') NOT NULL");
    }
};

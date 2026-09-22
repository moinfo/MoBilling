<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * One live "reply 1 to renew" WhatsApp session per (tenant, client phone),
 * written when SendDomainExpiryReminders sends a MoSMS-routed reminder and
 * consumed by the inbound webhook MoSMS forwards a bare "1" reply to —
 * MoSMS only tells us which tenant + phone replied, not which domain, so
 * this is what remembers that.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('whatsapp_renewal_sessions', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('client_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('domain_id')->constrained()->cascadeOnDelete();
            $table->string('phone', 16);
            // dateTime, not timestamp — MariaDB gives the first TIMESTAMP column in a table an
            // implicit "ON UPDATE CURRENT_TIMESTAMP", which silently resets this on every row
            // update that doesn't explicitly re-set it (see the later migration that fixed this live).
            $table->dateTime('expires_at');
            $table->timestamps();

            $table->unique(['tenant_id', 'phone']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('whatsapp_renewal_sessions');
    }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * One-time codes for sensitive WhatsApp actions (first use: cPanel password reset).
 * Additive only. Only a keyed hash of the code is stored. DATETIME (not TIMESTAMP) columns.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('whatsapp_otps')) {
            return;
        }
        Schema::create('whatsapp_otps', function (Blueprint $table) {
            $table->id();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('phone', 32);
            $table->uuid('client_id');
            $table->string('purpose', 64);
            $table->string('code_hash', 128);
            $table->unsignedSmallInteger('attempts')->default(0);
            $table->dateTime('expires_at');
            $table->dateTime('used_at')->nullable();
            $table->dateTime('created_at')->nullable();

            $table->index(['tenant_id', 'phone', 'purpose', 'used_at']);
            $table->index(['client_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('whatsapp_otps');
    }
};

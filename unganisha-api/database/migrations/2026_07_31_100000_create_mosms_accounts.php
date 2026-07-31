<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Link between a MoBilling tenant and their MoSMS account (mosms.co.tz).
 * WhatsApp messages are sent through MoSMS's token API — the tenant links
 * (or registers) their MoSMS account once and we store the Sanctum token.
 * Mirrors MoPOS's mosms_accounts table.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('mosms_accounts', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->unique()->constrained()->cascadeOnDelete();
            $table->unsignedBigInteger('mosms_tenant_id')->nullable();
            $table->string('email')->nullable();
            $table->text('token')->nullable();                       // encrypted Sanctum token
            $table->string('sender', 64)->nullable();
            // Cached id of MoSMS's approved 1-variable "custom_message" wrapper
            // template — required to send free text business-initiated.
            $table->unsignedBigInteger('custom_template_id')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('mosms_accounts');
    }
};

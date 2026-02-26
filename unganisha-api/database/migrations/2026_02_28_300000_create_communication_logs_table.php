<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('communication_logs', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('client_id')->nullable()->constrained()->nullOnDelete();
            $table->enum('channel', ['email', 'sms']);
            $table->string('type'); // notification class name e.g. 'invoice_sent'
            $table->string('recipient'); // email address or phone number
            $table->string('subject')->nullable(); // email subject (null for SMS)
            $table->text('message')->nullable(); // SMS body or email summary
            $table->enum('status', ['sent', 'failed']);
            $table->text('error')->nullable(); // error message if failed
            $table->json('metadata')->nullable(); // extra data (document_id, bill_id, etc.)
            $table->timestamp('created_at')->useCurrent();

            $table->index(['tenant_id', 'created_at']);
            $table->index(['client_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('communication_logs');
    }
};

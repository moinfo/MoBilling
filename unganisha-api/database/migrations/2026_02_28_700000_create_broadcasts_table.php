<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('broadcasts', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('sent_by')->constrained('users')->cascadeOnDelete();
            $table->json('client_ids')->nullable();
            $table->unsignedInteger('total_recipients');
            $table->enum('channel', ['email', 'sms', 'both']);
            $table->string('subject')->nullable();
            $table->text('body')->nullable();
            $table->text('sms_body')->nullable();
            $table->unsignedInteger('sent_count')->default(0);
            $table->unsignedInteger('failed_count')->default(0);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('broadcasts');
    }
};

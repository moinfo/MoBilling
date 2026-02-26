<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('followups', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('document_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('client_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignUuid('user_id')->nullable()->constrained()->nullOnDelete();
            $table->timestamp('call_date')->nullable();
            $table->enum('outcome', ['promised', 'declined', 'no_answer', 'disputed', 'partial_payment'])->nullable();
            $table->text('notes')->nullable();
            $table->date('promise_date')->nullable();
            $table->decimal('promise_amount', 14, 2)->nullable();
            $table->date('next_followup')->nullable();
            $table->enum('status', ['pending', 'open', 'fulfilled', 'broken', 'escalated', 'cancelled'])->default('pending');
            $table->timestamps();

            $table->index(['tenant_id', 'next_followup']);
            $table->index(['document_id', 'status']);
            $table->index(['user_id', 'next_followup']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('followups');
    }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('satisfaction_calls', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('client_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('user_id')->nullable()->constrained()->nullOnDelete();
            $table->date('scheduled_date');
            $table->timestamp('called_at')->nullable();
            $table->enum('outcome', [
                'satisfied', 'needs_improvement', 'complaint', 'suggestion', 'no_answer', 'unreachable',
            ])->nullable();
            $table->tinyInteger('rating')->nullable();
            $table->text('feedback')->nullable();
            $table->text('internal_notes')->nullable();
            $table->enum('status', ['scheduled', 'completed', 'missed', 'cancelled'])->default('scheduled');
            $table->string('month_key', 7); // e.g. "2026-03"
            $table->timestamps();

            $table->unique(['tenant_id', 'client_id', 'month_key'], 'satisfaction_tenant_client_month');
            $table->index(['tenant_id', 'scheduled_date']);
            $table->index(['tenant_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('satisfaction_calls');
    }
};

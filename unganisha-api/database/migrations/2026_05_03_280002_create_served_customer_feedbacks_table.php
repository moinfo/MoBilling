<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('served_customer_feedbacks', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('served_customer_id')->constrained('served_customers')->cascadeOnDelete();
            $table->timestamp('called_at')->useCurrent();
            $table->unsignedTinyInteger('rating')->nullable();        // 1–5
            $table->enum('outcome', ['satisfied', 'neutral', 'dissatisfied'])->nullable();
            $table->text('feedback')->nullable();                      // customer's words
            $table->text('challenges')->nullable();                    // issues/challenges raised
            $table->text('internal_notes')->nullable();
            $table->timestamps();

            $table->index(['tenant_id', 'served_customer_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('served_customer_feedbacks');
    }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('recurring_invoice_logs', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('client_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('product_service_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('document_id')->nullable()->constrained()->nullOnDelete();
            $table->date('next_bill_date');
            $table->timestamp('invoice_created_at')->nullable();
            $table->json('reminders_sent')->default('[]');
            $table->timestamps();

            $table->unique(['tenant_id', 'client_id', 'product_service_id', 'next_bill_date'], 'recurring_log_unique');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('recurring_invoice_logs');
    }
};

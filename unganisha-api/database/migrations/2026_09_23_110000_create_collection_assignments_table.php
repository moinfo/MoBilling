<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('collection_assignments', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('tenant_id')->index();
            $table->uuid('document_id')->index();
            $table->uuid('user_id')->index();
            $table->uuid('assigned_by')->nullable();
            $table->uuid('batch_id')->nullable()->index();
            $table->decimal('target_amount', 15, 2);
            $table->enum('commission_type', ['none', 'percentage', 'fixed'])->default('none');
            $table->decimal('commission_value', 15, 2)->default(0);
            $table->decimal('baseline_paid', 15, 2)->default(0);
            $table->enum('status', ['active', 'completed', 'cancelled'])->default('active');
            $table->timestamp('paid_out_at')->nullable();
            $table->uuid('paid_out_by')->nullable();
            $table->timestamps();
            $table->index(['document_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('collection_assignments');
    }
};

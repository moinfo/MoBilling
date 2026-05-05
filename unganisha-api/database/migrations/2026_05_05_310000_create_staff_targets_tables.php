<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('staff_targets', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('user_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('assigned_by')->constrained('users')->cascadeOnDelete();
            $table->string('title');
            $table->text('description')->nullable();
            $table->date('period_start');
            $table->date('period_end');
            // active → self_reported → verified | cancelled
            $table->enum('status', ['active', 'self_reported', 'verified', 'cancelled'])->default('active');
            $table->text('supervisor_notes')->nullable();
            $table->foreignUuid('verified_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('verified_at')->nullable();
            $table->timestamps();
        });

        Schema::create('staff_target_criteria', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('target_id')->constrained('staff_targets')->cascadeOnDelete();
            // customer_count | revenue | item_sales | custom
            $table->enum('type', ['customer_count', 'revenue', 'item_sales', 'custom']);
            $table->string('label');                   // "New customers", "Domain sales"
            $table->string('unit')->default('units'); // "customers", "KES", "domains"
            $table->decimal('goal_value', 15, 2);
            $table->decimal('achieved_value', 15, 2)->nullable();   // self-reported
            $table->decimal('verified_value', 15, 2)->nullable();   // supervisor-confirmed
            $table->boolean('goal_met')->nullable();
            $table->enum('commission_type', ['none', 'fixed', 'percentage'])->default('none');
            $table->decimal('commission_value', 15, 2)->nullable(); // amount or percent
            $table->decimal('commission_earned', 15, 2)->nullable(); // computed on verify
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('staff_target_criteria');
        Schema::dropIfExists('staff_targets');
    }
};
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('staff_report_penalties', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('user_id')->constrained()->cascadeOnDelete();
            $table->enum('report_type', ['daily', 'weekly', 'monthly']);
            $table->enum('penalty_type', ['missing', 'late']);
            $table->date('period_date');
            $table->decimal('amount', 12, 2);
            $table->foreignUuid('staff_report_id')->nullable()->constrained('staff_reports')->nullOnDelete();
            $table->string('notes')->nullable();
            $table->boolean('waived')->default(false);
            $table->timestamps();

            // one penalty per person / type / period — prevents double-charging on re-runs
            $table->unique(['user_id', 'report_type', 'penalty_type', 'period_date'], 'srp_unique');
            $table->index(['tenant_id', 'user_id', 'period_date']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('staff_report_penalties');
    }
};

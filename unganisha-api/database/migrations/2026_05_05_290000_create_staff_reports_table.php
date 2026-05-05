<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('staff_reports', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('user_id')->constrained()->cascadeOnDelete();
            $table->enum('report_type', ['daily', 'weekly', 'monthly']);
            $table->date('period_date'); // normalized: exact date / week Monday / month 1st
            $table->text('achievements')->nullable();
            $table->text('challenges')->nullable();
            $table->text('plans')->nullable();
            $table->text('notes')->nullable();
            $table->enum('status', ['submitted', 'reviewed'])->default('submitted');
            $table->foreignUuid('reviewed_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('reviewed_at')->nullable();
            $table->text('review_notes')->nullable();
            $table->tinyInteger('rating')->unsigned()->nullable(); // 1–5
            $table->timestamps();

            $table->unique(['tenant_id', 'user_id', 'report_type', 'period_date']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('staff_reports');
    }
};

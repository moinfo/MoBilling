<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
return new class extends Migration {
    public function up(): void {
        Schema::create('attendance_penalties', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('user_id')->constrained()->cascadeOnDelete();
            $table->date('date');
            $table->enum('penalty_type', ['absent', 'late', 'left_early', 'no_checkout']);
            $table->decimal('amount', 12, 2);
            $table->string('notes')->nullable();
            $table->boolean('waived')->default(false);
            $table->foreignUuid('waived_by')->nullable();
            $table->timestamp('waived_at')->nullable();
            $table->string('waive_reason')->nullable();
            $table->timestamps();
            $table->unique(['user_id', 'date', 'penalty_type'], 'attn_pen_unique');
            $table->index(['tenant_id', 'user_id', 'date']);
        });
    }
    public function down(): void { Schema::dropIfExists('attendance_penalties'); }
};

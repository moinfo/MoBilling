<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Historical, not overwritten — a raise inserts a new row rather than
 * mutating the old one, so a payroll run always uses whichever salary was
 * actually effective for that period even after a later change.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('staff_salaries', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('user_id')->constrained()->cascadeOnDelete();
            $table->decimal('basic_salary', 12, 2);
            $table->date('effective_from');
            $table->text('notes')->nullable();
            $table->timestamps();

            $table->index(['tenant_id', 'user_id', 'effective_from']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('staff_salaries');
    }
};

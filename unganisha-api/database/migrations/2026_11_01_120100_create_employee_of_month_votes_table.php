<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * One vote per (cycle, voter) — the unique index is the enforcement that a
 * staff member can only vote once per cycle. "Can't vote for yourself" is
 * validated in the controller, not the DB, same as every other business
 * rule in this app.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('employee_of_month_votes', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('cycle_id')->constrained('employee_of_month_cycles')->cascadeOnDelete();
            $table->foreignUuid('voter_id')->constrained('users')->cascadeOnDelete();
            $table->foreignUuid('candidate_id')->constrained('users')->cascadeOnDelete();
            $table->text('reason');
            $table->timestamps();

            $table->unique(['cycle_id', 'voter_id']);
            $table->index(['cycle_id', 'candidate_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('employee_of_month_votes');
    }
};

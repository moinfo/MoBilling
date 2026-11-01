<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * One row per tenant per month being voted on. Voting for the PREVIOUS
 * month's best employee runs the 1st-3rd of the following month — opened
 * and closed by scheduled commands (eotm:open-voting / eotm:close-voting),
 * never by hand, so the window is always the same three days.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('employee_of_month_cycles', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('period_month_key'); // the month being voted ON, e.g. "2026-10"
            $table->date('voting_opens_on');
            $table->date('voting_closes_on');
            $table->decimal('prize_amount', 12, 2)->nullable();
            $table->enum('status', ['open', 'closed'])->default('open');
            $table->foreignUuid('winner_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->unsignedInteger('winner_vote_count')->nullable();
            $table->foreignUuid('winner_commission_id')->nullable()->constrained('commissions')->nullOnDelete();
            $table->timestamp('tallied_at')->nullable();
            $table->timestamps();

            $table->unique(['tenant_id', 'period_month_key']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('employee_of_month_cycles');
    }
};

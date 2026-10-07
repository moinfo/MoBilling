<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The daily check-in's real purpose: confirm the client actually closed out
 * their system for the day, by having the verifying staff read off and
 * record the real figures (cash on hand, sales, outstanding credit, and the
 * resulting gain or loss) rather than just a pass/fail opinion.
 *
 * gain_loss is one signed column (negative = loss), not two — simpler to
 * report and chart, and "loss" is naturally just a negative gain.
 *
 * submitted_on_time is recorded AT SUBMISSION TIME against whatever the
 * tenant's window was then, not computed later — the window can change,
 * and history should reflect the rule that was actually in force when the
 * report was filed.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('system_verification_reports', function (Blueprint $table) {
            $table->decimal('cash', 14, 2)->nullable()->after('status');
            $table->decimal('sales', 14, 2)->nullable()->after('cash');
            $table->decimal('credit', 14, 2)->nullable()->after('sales');
            $table->decimal('gain_loss', 14, 2)->nullable()->after('credit');
            $table->boolean('submitted_on_time')->nullable()->after('gain_loss');
        });
    }

    public function down(): void
    {
        Schema::table('system_verification_reports', function (Blueprint $table) {
            $table->dropColumn(['cash', 'sales', 'credit', 'gain_loss', 'submitted_on_time']);
        });
    }
};

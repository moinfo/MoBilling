<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Daily check-in reports submitted by the assigned staff. One row per
     * (system, report_date) — the UNIQUE constraint enforces "one report per
     * system per day" so we can't accidentally double-count and so cron
     * reminders have a deterministic "is today done?" check.
     *
     * notes are required when status='issue' (enforced at the request layer,
     * not the schema, so admin can later soften the rule without a migration).
     */
    public function up(): void
    {
        Schema::create('system_verification_reports', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('system_verification_id')->constrained('system_verifications')->cascadeOnDelete();
            $table->foreignUuid('user_id')->constrained('users')->cascadeOnDelete();
            $table->date('report_date');
            $table->enum('status', ['ok', 'issue']);
            $table->text('notes')->nullable();
            $table->timestamps();
            $table->softDeletes();

            // Custom-named because the auto-generated name
            // (system_verification_reports_system_verification_id_report_date_unique, 65 chars)
            // exceeds MySQL's 64-char identifier limit.
            $table->unique(['system_verification_id', 'report_date'], 'svr_system_date_unique');
            $table->index(['tenant_id', 'report_date']);
            $table->index('user_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('system_verification_reports');
    }
};

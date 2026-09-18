<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Per-account retention policy for the automated paid-backup job
     * (hosting:backup-paid-accounts). One row per hosting account that has
     * customized it — no row means "use the defaults" (7 daily, keep 1
     * weekly, keep 1 monthly), so nothing needs backfilling for existing
     * accounts.
     */
    public function up(): void
    {
        Schema::create('hosting_account_backup_settings', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('hosting_account_id')->unique()->constrained()->cascadeOnDelete();
            $table->unsignedTinyInteger('daily_retention_days')->default(7);
            $table->boolean('keep_weekly')->default(true);
            $table->boolean('keep_monthly')->default(true);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('hosting_account_backup_settings');
    }
};

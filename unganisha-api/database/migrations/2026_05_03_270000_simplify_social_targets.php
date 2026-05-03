<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Add new columns if missing (idempotent)
        if (!Schema::hasColumn('social_targets', 'image_target')) {
            DB::statement('ALTER TABLE social_targets ADD COLUMN image_target SMALLINT UNSIGNED NOT NULL DEFAULT 3');
        }
        if (!Schema::hasColumn('social_targets', 'video_target')) {
            DB::statement('ALTER TABLE social_targets ADD COLUMN video_target SMALLINT UNSIGNED NOT NULL DEFAULT 2');
        }

        // Drop FK if it still exists
        $fks = collect(DB::select("
            SELECT CONSTRAINT_NAME FROM information_schema.TABLE_CONSTRAINTS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'social_targets'
              AND CONSTRAINT_TYPE = 'FOREIGN KEY'
              AND CONSTRAINT_NAME = 'social_targets_user_id_foreign'
        "));
        if ($fks->isNotEmpty()) {
            DB::statement('ALTER TABLE social_targets DROP FOREIGN KEY social_targets_user_id_foreign');
        }

        // Drop unique index — but first add a plain index on tenant_id so the FK stays satisfied
        $indexes = collect(DB::select("SHOW INDEX FROM social_targets WHERE Key_name = 'social_targets_tenant_id_user_id_metric_unique'"));
        if ($indexes->isNotEmpty()) {
            $hasTenantIdx = collect(DB::select("SHOW INDEX FROM social_targets WHERE Key_name = 'social_targets_tenant_id_index'"))->isNotEmpty();
            if (!$hasTenantIdx) {
                DB::statement('CREATE INDEX social_targets_tenant_id_index ON social_targets (tenant_id)');
            }
            DB::statement('ALTER TABLE social_targets DROP INDEX social_targets_tenant_id_user_id_metric_unique');
        }

        // Drop old columns if they exist
        foreach (['user_id', 'metric', 'daily_target', 'weekly_target'] as $col) {
            if (Schema::hasColumn('social_targets', $col)) {
                DB::statement("ALTER TABLE social_targets DROP COLUMN `{$col}`");
            }
        }

        // Keep only one row per tenant (the latest)
        DB::statement("
            DELETE t1 FROM social_targets t1
            INNER JOIN social_targets t2
            WHERE t1.tenant_id = t2.tenant_id AND t1.created_at < t2.created_at
        ");
    }

    public function down(): void {}
};

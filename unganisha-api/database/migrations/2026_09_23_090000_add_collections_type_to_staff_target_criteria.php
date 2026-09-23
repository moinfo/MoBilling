<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * "collections" is a new criterion type whose achieved/verified value is computed
 * automatically from what the staff member's assigned Followups actually collected
 * (StaffTargetsController::autoVerifyCollections()), instead of self-reported + manually
 * verified like the existing types.
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::statement("ALTER TABLE staff_target_criteria MODIFY type ENUM('customer_count', 'revenue', 'item_sales', 'custom', 'collections') NOT NULL");
    }

    public function down(): void
    {
        DB::statement("ALTER TABLE staff_target_criteria MODIFY type ENUM('customer_count', 'revenue', 'item_sales', 'custom') NOT NULL");
    }
};

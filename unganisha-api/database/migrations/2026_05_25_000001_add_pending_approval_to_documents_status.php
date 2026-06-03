<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /**
     * The approval workflow (submitForApproval / approve / reject) reads and writes
     * the 'pending_approval' status, but no migration ever added it to the enum —
     * it only exists in the live DB via a manual ALTER. Under STRICT_TRANS_TABLES a
     * fresh deploy would reject that value, breaking submit-for-approval. This brings
     * the schema in line with the application.
     */
    public function up(): void
    {
        DB::statement("ALTER TABLE documents MODIFY COLUMN status ENUM('draft','pending_approval','sent','accepted','rejected','paid','overdue','partial','cancelled') DEFAULT 'draft'");
    }

    public function down(): void
    {
        // Move any pending_approval rows back to draft before dropping the value,
        // otherwise the MODIFY would fail / coerce them.
        DB::table('documents')->where('status', 'pending_approval')->update(['status' => 'draft']);

        DB::statement("ALTER TABLE documents MODIFY COLUMN status ENUM('draft','sent','accepted','rejected','paid','overdue','partial','cancelled') DEFAULT 'draft'");
    }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        DB::statement("ALTER TABLE documents MODIFY COLUMN status ENUM('draft','pending_approval','sent','accepted','rejected','paid','overdue','partial','cancelled') DEFAULT 'draft'");
    }

    public function down(): void
    {
        DB::statement("ALTER TABLE documents MODIFY COLUMN status ENUM('draft','sent','accepted','rejected','paid','overdue','partial','cancelled') DEFAULT 'draft'");
    }
};

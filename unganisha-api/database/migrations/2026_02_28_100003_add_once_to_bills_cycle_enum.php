<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        DB::statement("ALTER TABLE bills MODIFY COLUMN cycle ENUM('once', 'monthly', 'quarterly', 'half_yearly', 'yearly') NOT NULL");
    }

    public function down(): void
    {
        DB::statement("ALTER TABLE bills MODIFY COLUMN cycle ENUM('monthly', 'quarterly', 'half_yearly', 'yearly') NOT NULL");
    }
};

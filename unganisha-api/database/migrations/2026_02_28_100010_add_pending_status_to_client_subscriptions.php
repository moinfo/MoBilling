<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        DB::statement("ALTER TABLE client_subscriptions MODIFY COLUMN status ENUM('pending','active','cancelled','suspended') DEFAULT 'pending'");
    }

    public function down(): void
    {
        DB::statement("ALTER TABLE client_subscriptions MODIFY COLUMN status ENUM('active','cancelled','suspended') DEFAULT 'active'");
    }
};

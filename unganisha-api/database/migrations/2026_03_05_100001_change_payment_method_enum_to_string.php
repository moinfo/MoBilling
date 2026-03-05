<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        DB::statement("ALTER TABLE payments_in MODIFY COLUMN payment_method VARCHAR(50) NOT NULL");
        DB::statement("ALTER TABLE payments_out MODIFY COLUMN payment_method VARCHAR(50) NOT NULL");
        DB::statement("ALTER TABLE expenses MODIFY COLUMN payment_method VARCHAR(50) NOT NULL");
    }

    public function down(): void
    {
        DB::statement("ALTER TABLE payments_in MODIFY COLUMN payment_method ENUM('cash','bank','mpesa','card','other') NOT NULL");
        DB::statement("ALTER TABLE payments_out MODIFY COLUMN payment_method ENUM('cash','bank','mpesa','card','other') NOT NULL");
        DB::statement("ALTER TABLE expenses MODIFY COLUMN payment_method ENUM('cash','bank','mpesa','card','other') NOT NULL");
    }
};

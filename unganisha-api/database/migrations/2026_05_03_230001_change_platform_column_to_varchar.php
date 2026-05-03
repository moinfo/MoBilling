<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

// Change social_post_platforms.platform from ENUM to VARCHAR so custom platforms work
return new class extends Migration
{
    public function up(): void
    {
        DB::statement('ALTER TABLE social_post_platforms MODIFY COLUMN platform VARCHAR(50) NOT NULL');
    }

    public function down(): void
    {
        DB::statement("ALTER TABLE social_post_platforms MODIFY COLUMN platform ENUM('instagram','facebook','threads','x','tiktok') NOT NULL");
    }
};

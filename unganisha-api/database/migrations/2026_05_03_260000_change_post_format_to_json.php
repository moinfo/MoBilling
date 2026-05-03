<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        // Add JSON column alongside the old ENUM
        DB::statement('ALTER TABLE social_posts ADD COLUMN post_format_json JSON NULL AFTER post_format');

        // Migrate: wrap existing single values into JSON arrays
        DB::statement("UPDATE social_posts SET post_format_json = JSON_ARRAY(COALESCE(post_format, 'feed_post'))");

        // Drop old ENUM column, rename new one
        DB::statement('ALTER TABLE social_posts DROP COLUMN post_format');
        DB::statement('ALTER TABLE social_posts RENAME COLUMN post_format_json TO post_format');
    }

    public function down(): void
    {
        // Restore ENUM by taking the first element
        DB::statement("ALTER TABLE social_posts ADD COLUMN post_format_enum ENUM('feed_post','reel','story','carousel') NOT NULL DEFAULT 'feed_post' AFTER post_format");
        DB::statement("UPDATE social_posts SET post_format_enum = COALESCE(JSON_UNQUOTE(JSON_EXTRACT(post_format, '$[0]')), 'feed_post')");
        DB::statement('ALTER TABLE social_posts DROP COLUMN post_format');
        DB::statement('ALTER TABLE social_posts RENAME COLUMN post_format_enum TO post_format');
    }
};

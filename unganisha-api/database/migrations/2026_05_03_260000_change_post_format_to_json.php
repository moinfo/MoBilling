<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        $hasOld = Schema::hasColumn('social_posts', 'post_format');
        $hasNew = Schema::hasColumn('social_posts', 'post_format_json');

        if ($hasOld && ! $hasNew) {
            DB::statement('ALTER TABLE social_posts ADD COLUMN post_format_json JSON NULL AFTER post_format');
            DB::statement("UPDATE social_posts SET post_format_json = JSON_ARRAY(COALESCE(post_format, 'feed_post'))");
            DB::statement('ALTER TABLE social_posts DROP COLUMN post_format');
            DB::statement('ALTER TABLE social_posts CHANGE COLUMN post_format_json post_format JSON NULL');
        } elseif (! $hasOld && $hasNew) {
            DB::statement('ALTER TABLE social_posts CHANGE COLUMN post_format_json post_format JSON NULL');
        } elseif ($hasOld && $hasNew) {
            DB::statement("UPDATE social_posts SET post_format_json = JSON_ARRAY(COALESCE(post_format, 'feed_post')) WHERE post_format_json IS NULL");
            DB::statement('ALTER TABLE social_posts DROP COLUMN post_format');
            DB::statement('ALTER TABLE social_posts CHANGE COLUMN post_format_json post_format JSON NULL');
        }
    }

    public function down(): void
    {
        DB::statement("ALTER TABLE social_posts ADD COLUMN post_format_enum ENUM('feed_post','reel','story','carousel') NOT NULL DEFAULT 'feed_post' AFTER post_format");
        DB::statement("UPDATE social_posts SET post_format_enum = COALESCE(JSON_UNQUOTE(JSON_EXTRACT(post_format, '$[0]')), 'feed_post')");
        DB::statement('ALTER TABLE social_posts DROP COLUMN post_format');
        DB::statement("ALTER TABLE social_posts CHANGE COLUMN post_format_enum post_format ENUM('feed_post','reel','story','carousel') NOT NULL DEFAULT 'feed_post'");
    }
};

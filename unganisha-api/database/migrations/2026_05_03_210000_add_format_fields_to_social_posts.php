<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('social_posts', function (Blueprint $table) {
            $table->enum('post_format', ['feed_post', 'reel', 'story', 'carousel'])
                  ->default('feed_post')
                  ->after('type');
            $table->enum('media_type', ['image', 'video'])
                  ->default('image')
                  ->after('post_format');
            $table->time('scheduled_time')->nullable()->after('scheduled_date');
            $table->text('hashtags')->nullable()->after('caption');
        });
    }

    public function down(): void
    {
        Schema::table('social_posts', function (Blueprint $table) {
            $table->dropColumn(['post_format', 'media_type', 'scheduled_time', 'hashtags']);
        });
    }
};

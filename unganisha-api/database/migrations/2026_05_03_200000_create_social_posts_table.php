<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('social_posts', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('tenant_id');
            $table->string('title');
            $table->enum('type', ['product_education', 'holiday', 'employee_birthday', 'promotion', 'announcement', 'general'])->default('general');
            $table->date('scheduled_date');
            $table->text('brief')->nullable();
            $table->text('caption')->nullable();
            $table->string('design_file_url')->nullable();
            $table->text('design_notes')->nullable();
            $table->uuid('assigned_designer_id')->nullable();
            $table->uuid('assigned_creator_id')->nullable();
            $table->enum('design_status', ['pending', 'in_progress', 'done'])->default('pending');
            $table->enum('content_status', ['pending', 'ready'])->default('pending');
            $table->enum('status', ['planned', 'designing', 'content_ready', 'partial_posted', 'posted'])->default('planned');
            $table->uuid('created_by');
            $table->timestamps();

            $table->foreign('tenant_id')->references('id')->on('tenants')->cascadeOnDelete();
            $table->foreign('assigned_designer_id')->references('id')->on('users')->nullOnDelete();
            $table->foreign('assigned_creator_id')->references('id')->on('users')->nullOnDelete();
            $table->foreign('created_by')->references('id')->on('users');
            $table->index(['tenant_id', 'scheduled_date']);
        });

        Schema::create('social_post_platforms', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('social_post_id');
            $table->enum('platform', ['instagram', 'facebook', 'threads', 'x', 'tiktok']);
            $table->boolean('posted')->default(false);
            $table->timestamp('posted_at')->nullable();
            $table->string('post_url')->nullable();
            $table->uuid('posted_by')->nullable();
            $table->timestamps();

            $table->foreign('social_post_id')->references('id')->on('social_posts')->cascadeOnDelete();
            $table->foreign('posted_by')->references('id')->on('users')->nullOnDelete();
            $table->unique(['social_post_id', 'platform']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('social_post_platforms');
        Schema::dropIfExists('social_posts');
    }
};

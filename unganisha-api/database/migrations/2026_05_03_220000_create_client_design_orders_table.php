<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('client_design_orders', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('tenant_id')->index();
            $table->uuid('client_id')->nullable();
            $table->foreign('client_id')->references('id')->on('clients')->nullOnDelete();
            $table->string('title');
            $table->enum('design_type', [
                'logo', 'flyer', 'brochure', 'business_card', 'banner',
                'book_cover', 'label_poster', 'social_media_graphic',
                'merchandise', 'other',
            ])->default('flyer');
            $table->text('description')->nullable();
            $table->string('reference_url', 1000)->nullable();
            $table->uuid('assigned_designer_id')->nullable();
            $table->foreign('assigned_designer_id')->references('id')->on('users')->nullOnDelete();
            $table->enum('status', ['pending', 'in_progress', 'needs_revision', 'done', 'delivered'])->default('pending');
            $table->date('due_date')->nullable();
            $table->string('file_url', 1000)->nullable();
            $table->unsignedTinyInteger('revision_count')->default(0);
            $table->text('revision_notes')->nullable();
            $table->decimal('price', 10, 2)->nullable();
            $table->uuid('created_by')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('client_design_orders');
    }
};

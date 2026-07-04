<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('kb_articles', function (Blueprint $t) {
            $t->uuid('id')->primary();
            $t->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $t->foreignUuid('kb_category_id')->nullable()->constrained('kb_categories')->nullOnDelete();
            $t->string('title');
            $t->string('slug');
            $t->longText('body');
            $t->boolean('is_published')->default(false);
            $t->integer('views')->default(0);
            $t->integer('sort_order')->default(0);
            $t->timestamps();
            $t->softDeletes();
            $t->unique(['tenant_id', 'slug']);
            $t->index(['tenant_id', 'is_published', 'sort_order']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('kb_articles');
    }
};

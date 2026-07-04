<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('canned_replies', function (Blueprint $t) {
            $t->uuid('id')->primary();
            $t->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $t->string('title');
            $t->longText('body');
            $t->timestamps();
            $t->softDeletes();
            $t->index(['tenant_id', 'title']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('canned_replies');
    }
};

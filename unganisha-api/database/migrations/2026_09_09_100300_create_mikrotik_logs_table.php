<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('mikrotik_logs', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('mikrotik_router_id')->constrained()->cascadeOnDelete();
            $table->string('action');
            $table->json('request')->nullable();
            $table->json('response')->nullable();
            $table->string('status');
            $table->text('error')->nullable();
            $table->timestamps();

            $table->index(['tenant_id', 'mikrotik_router_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('mikrotik_logs');
    }
};

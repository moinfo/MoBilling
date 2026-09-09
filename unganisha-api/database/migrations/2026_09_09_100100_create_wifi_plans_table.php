<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('wifi_plans', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('mikrotik_router_id')->constrained()->cascadeOnDelete();
            $table->string('name');
            $table->unsignedInteger('duration_value');
            $table->enum('duration_unit', ['hours', 'days', 'weeks']);
            $table->decimal('price', 12, 2);
            // The RouterOS "user profile" to assign (e.g. a speed-limit
            // profile already configured on the router) — nullable, falls
            // back to the router's "default" hotspot profile.
            $table->string('hotspot_profile')->nullable();
            $table->boolean('is_active')->default(true);
            $table->timestamps();
            $table->softDeletes();

            $table->index(['tenant_id', 'mikrotik_router_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('wifi_plans');
    }
};

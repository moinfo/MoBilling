<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('subscription_plan_permissions', function (Blueprint $table) {
            $table->uuid('subscription_plan_id');
            $table->uuid('permission_id');
            $table->primary(['subscription_plan_id', 'permission_id']);
            $table->foreign('subscription_plan_id')->references('id')->on('subscription_plans')->cascadeOnDelete();
            $table->foreign('permission_id')->references('id')->on('permissions')->cascadeOnDelete();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('subscription_plan_permissions');
    }
};

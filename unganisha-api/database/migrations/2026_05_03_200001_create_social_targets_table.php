<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('social_targets', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('tenant_id');
            $table->uuid('user_id');
            $table->enum('metric', ['designs', 'posts']);       // what's being tracked
            $table->unsignedSmallInteger('weekly_target');      // total expected per week
            $table->unsignedTinyInteger('daily_target');        // expected per active day
            $table->json('active_days');                        // ISO weekdays [1=Mon … 7=Sun]
            $table->date('effective_from');
            $table->timestamps();

            $table->foreign('tenant_id')->references('id')->on('tenants')->cascadeOnDelete();
            $table->foreign('user_id')->references('id')->on('users')->cascadeOnDelete();
            $table->unique(['tenant_id', 'user_id', 'metric']); // one target config per person per metric
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('social_targets');
    }
};

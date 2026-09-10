<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Lets a plan be pure data (e.g. "5GB, no time limit — good until
        // it's used up") with no duration_value/duration_unit at all.
        // StoreWifiPlanRequest enforces that a plan always has at least
        // one of {duration, data_cap_mb} set.
        Schema::table('wifi_plans', function (Blueprint $table) {
            $table->unsignedInteger('duration_value')->nullable()->change();
            $table->enum('duration_unit', ['hours', 'days', 'weeks'])->nullable()->change();
        });
    }

    public function down(): void
    {
        Schema::table('wifi_plans', function (Blueprint $table) {
            $table->unsignedInteger('duration_value')->nullable(false)->change();
            $table->enum('duration_unit', ['hours', 'days', 'weeks'])->nullable(false)->change();
        });
    }
};

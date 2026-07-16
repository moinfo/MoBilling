<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('staff_report_settings', function (Blueprint $table) {
            $table->boolean('penalties_enabled')->default(true)->after('monthly_deadline_time');
            $table->decimal('penalty_missing_daily', 12, 2)->default(5000)->after('penalties_enabled');
            $table->decimal('penalty_late', 12, 2)->default(2000)->after('penalty_missing_daily');
            $table->decimal('penalty_missing_weekly', 12, 2)->default(7000)->after('penalty_late');
            $table->decimal('penalty_missing_monthly', 12, 2)->default(10000)->after('penalty_missing_weekly');
        });
    }

    public function down(): void
    {
        Schema::table('staff_report_settings', function (Blueprint $table) {
            $table->dropColumn(['penalties_enabled', 'penalty_missing_daily', 'penalty_late', 'penalty_missing_weekly', 'penalty_missing_monthly']);
        });
    }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('staff_report_settings', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->unique()->constrained()->cascadeOnDelete();
            // Monthly submission targets
            $table->unsignedSmallInteger('daily_target')->default(20);
            $table->unsignedSmallInteger('weekly_target')->default(4);
            $table->unsignedSmallInteger('monthly_target')->default(1);
            // Deadlines: daily = same day at HH:mm
            $table->string('daily_deadline_time', 5)->default('18:00');
            // Weekly = day-of-week (1=Mon … 7=Sun) at HH:mm (period_date is Monday)
            $table->unsignedTinyInteger('weekly_deadline_day')->default(5);
            $table->string('weekly_deadline_time', 5)->default('17:00');
            // Monthly = day-of-month (1–28) at HH:mm (period_date is 1st of month)
            $table->unsignedTinyInteger('monthly_deadline_day')->default(28);
            $table->string('monthly_deadline_time', 5)->default('17:00');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('staff_report_settings');
    }
};
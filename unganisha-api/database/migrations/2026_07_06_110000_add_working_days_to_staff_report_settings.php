<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('staff_report_settings', function (Blueprint $table) {
            // ISO weekdays that require a daily report (1=Mon … 7=Sun). Default Mon–Sat.
            $table->json('working_days')->nullable()->after('monthly_deadline_time');
        });
    }

    public function down(): void
    {
        Schema::table('staff_report_settings', function (Blueprint $table) {
            $table->dropColumn('working_days');
        });
    }
};

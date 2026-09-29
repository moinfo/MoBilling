<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * On-time / late tracking for follow-up calls: set once in FollowupController::logCall by comparing
 * call_date against the followup row's next_followup (the date the call was actually due). Both nullable
 * because older rows, and any row whose due date was never set, have nothing to compare against.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('followups', function (Blueprint $table) {
            $table->boolean('completed_on_time')->nullable()->after('status');
            $table->unsignedInteger('days_late')->nullable()->after('completed_on_time');
        });
    }

    public function down(): void
    {
        Schema::table('followups', function (Blueprint $table) {
            $table->dropColumn(['completed_on_time', 'days_late']);
        });
    }
};

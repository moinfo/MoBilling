<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Add follow_up_of column to track auto-rescheduled satisfaction calls
 * when a client doesn't answer or is unreachable.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('satisfaction_calls', function (Blueprint $table) {
            $table->uuid('follow_up_of')->nullable()->after('month_key');
            $table->foreign('follow_up_of')->references('id')->on('satisfaction_calls')->nullOnDelete();
        });

        // Drop the unique constraint so follow-up calls can exist for the same client+month
        Schema::table('satisfaction_calls', function (Blueprint $table) {
            $table->dropUnique('satisfaction_tenant_client_month');
        });
    }

    public function down(): void
    {
        Schema::table('satisfaction_calls', function (Blueprint $table) {
            $table->unique(['tenant_id', 'client_id', 'month_key'], 'satisfaction_tenant_client_month');
        });

        Schema::table('satisfaction_calls', function (Blueprint $table) {
            $table->dropForeign(['follow_up_of']);
            $table->dropColumn('follow_up_of');
        });
    }
};

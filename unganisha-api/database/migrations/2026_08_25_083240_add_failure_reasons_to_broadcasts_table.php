<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('broadcasts', function (Blueprint $table) {
            // Map of client_id => the exception message that send failed with —
            // shown alongside failed_client_ids so staff can see WHY, not just who.
            $table->json('failure_reasons')->nullable()->after('failed_client_ids');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('broadcasts', function (Blueprint $table) {
            $table->dropColumn('failure_reasons');
        });
    }
};

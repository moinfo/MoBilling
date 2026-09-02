<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        // Widening an enum via Schema::table()->change() needs doctrine/dbal
        // for its column introspection; a raw MODIFY sidesteps that entirely.
        DB::statement("ALTER TABLE broadcasts MODIFY channel ENUM('email', 'sms', 'whatsapp', 'both') NOT NULL");

        Schema::table('broadcasts', function (Blueprint $table) {
            $table->text('whatsapp_body')->nullable()->after('sms_body');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('broadcasts', function (Blueprint $table) {
            $table->dropColumn('whatsapp_body');
        });

        DB::statement("ALTER TABLE broadcasts MODIFY channel ENUM('email', 'sms', 'both') NOT NULL");
    }
};

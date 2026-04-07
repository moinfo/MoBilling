<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('field_visits', function (Blueprint $table) {
            $table->date('next_followup_date')->nullable()->after('client_id');
        });
    }

    public function down(): void
    {
        Schema::table('field_visits', function (Blueprint $table) {
            $table->dropColumn('next_followup_date');
        });
    }
};

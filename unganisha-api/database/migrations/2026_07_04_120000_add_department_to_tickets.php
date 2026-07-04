<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tickets', function (Blueprint $table) {
            $table->string('department', 30)->default('support')->after('subject');
            // free-text label of the service the ticket is about, e.g. "Hosting: example.co.tz"
            $table->string('related_service')->nullable()->after('department');
        });
    }

    public function down(): void
    {
        Schema::table('tickets', function (Blueprint $table) {
            $table->dropColumn(['department', 'related_service']);
        });
    }
};

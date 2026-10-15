<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('system_verifications', function (Blueprint $table) {
            $table->string('support_contact_name')->nullable()->after('required_fields');
            $table->string('support_contact_phone')->nullable()->after('support_contact_name');
        });
    }

    public function down(): void
    {
        Schema::table('system_verifications', function (Blueprint $table) {
            $table->dropColumn(['support_contact_name', 'support_contact_phone']);
        });
    }
};

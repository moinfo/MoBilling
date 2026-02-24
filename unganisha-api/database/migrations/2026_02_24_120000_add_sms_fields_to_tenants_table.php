<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->boolean('sms_enabled')->default(false)->after('smtp_from_name');
            $table->string('gateway_email')->nullable()->after('sms_enabled');
            $table->string('gateway_username')->nullable()->after('gateway_email');
            $table->string('sender_id')->nullable()->after('gateway_username');
            $table->text('sms_authorization')->nullable()->after('sender_id');
        });
    }

    public function down(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->dropColumn(['sms_enabled', 'gateway_email', 'gateway_username', 'sender_id', 'sms_authorization']);
        });
    }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->boolean('whatsapp_enabled')->default(false)->after('sms_authorization');
            $table->boolean('reminder_whatsapp_enabled')->default(false)->after('whatsapp_enabled');
            $table->string('whatsapp_phone_number_id')->nullable()->after('reminder_whatsapp_enabled');
            $table->text('whatsapp_access_token')->nullable()->after('whatsapp_phone_number_id');
            $table->string('whatsapp_business_account_id')->nullable()->after('whatsapp_access_token');
        });
    }

    public function down(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->dropColumn([
                'whatsapp_enabled',
                'reminder_whatsapp_enabled',
                'whatsapp_phone_number_id',
                'whatsapp_access_token',
                'whatsapp_business_account_id',
            ]);
        });
    }
};

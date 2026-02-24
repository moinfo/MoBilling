<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->string('reminder_email_subject')->nullable();
            $table->text('reminder_email_body')->nullable();
            $table->string('overdue_email_subject')->nullable();
            $table->text('overdue_email_body')->nullable();
            $table->string('reminder_sms_body')->nullable();
            $table->string('overdue_sms_body')->nullable();
            $table->boolean('reminder_sms_enabled')->default(false);
            $table->boolean('reminder_email_enabled')->default(true);
        });
    }

    public function down(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->dropColumn([
                'reminder_email_subject', 'reminder_email_body',
                'overdue_email_subject', 'overdue_email_body',
                'reminder_sms_body', 'overdue_sms_body',
                'reminder_sms_enabled', 'reminder_email_enabled',
            ]);
        });
    }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->string('invoice_email_subject')->nullable()->after('overdue_sms_body');
            $table->text('invoice_email_body')->nullable()->after('invoice_email_subject');
        });
    }

    public function down(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->dropColumn(['invoice_email_subject', 'invoice_email_body']);
        });
    }
};

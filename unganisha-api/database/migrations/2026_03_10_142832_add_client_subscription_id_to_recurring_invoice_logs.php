<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('recurring_invoice_logs', function (Blueprint $table) {
            $table->uuid('client_subscription_id')->nullable()->after('product_service_id');
            $table->foreign('client_subscription_id')->references('id')->on('client_subscriptions')->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('recurring_invoice_logs', function (Blueprint $table) {
            $table->dropForeign(['client_subscription_id']);
            $table->dropColumn('client_subscription_id');
        });
    }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('client_subscriptions', function (Blueprint $table) {
            // WHMCS-style per-service billing overrides (null = derive from product)
            $table->decimal('first_payment_amount', 15, 2)->nullable()->after('discount_value');
            $table->decimal('recurring_amount', 15, 2)->nullable()->after('first_payment_amount');
            $table->string('payment_method', 50)->nullable()->after('recurring_amount');
            $table->string('promo_code', 50)->nullable()->after('payment_method');
        });
    }

    public function down(): void
    {
        Schema::table('client_subscriptions', function (Blueprint $table) {
            $table->dropColumn(['first_payment_amount', 'recurring_amount', 'payment_method', 'promo_code']);
        });
    }
};

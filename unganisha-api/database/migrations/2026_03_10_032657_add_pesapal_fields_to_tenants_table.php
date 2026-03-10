<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->boolean('pesapal_enabled')->default(false)->after('payment_methods');
            $table->string('pesapal_consumer_key')->nullable()->after('pesapal_enabled');
            $table->text('pesapal_consumer_secret')->nullable()->after('pesapal_consumer_key');
            $table->string('pesapal_ipn_id')->nullable()->after('pesapal_consumer_secret');
            $table->boolean('pesapal_sandbox')->default(false)->after('pesapal_ipn_id');
        });
    }

    public function down(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->dropColumn([
                'pesapal_enabled',
                'pesapal_consumer_key',
                'pesapal_consumer_secret',
                'pesapal_ipn_id',
                'pesapal_sandbox',
            ]);
        });
    }
};

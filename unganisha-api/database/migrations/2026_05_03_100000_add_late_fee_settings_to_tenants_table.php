<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->boolean('late_fee_enabled')->default(false)->after('subscription_grace_days');
            $table->decimal('late_fee_percent', 5, 2)->default(10.00)->after('late_fee_enabled');
            $table->unsignedTinyInteger('late_fee_days')->default(1)->after('late_fee_percent');
        });
    }

    public function down(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->dropColumn(['late_fee_enabled', 'late_fee_percent', 'late_fee_days']);
        });
    }
};

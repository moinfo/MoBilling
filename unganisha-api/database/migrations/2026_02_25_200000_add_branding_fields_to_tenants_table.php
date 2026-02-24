<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->string('website')->nullable()->after('phone');
            $table->string('logo_path')->nullable()->after('website');
            $table->string('bank_name')->nullable()->after('logo_path');
            $table->string('bank_account_name')->nullable()->after('bank_name');
            $table->string('bank_account_number')->nullable()->after('bank_account_name');
            $table->string('bank_branch')->nullable()->after('bank_account_number');
            $table->text('payment_instructions')->nullable()->after('bank_branch');
        });
    }

    public function down(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->dropColumn([
                'website', 'logo_path',
                'bank_name', 'bank_account_name', 'bank_account_number', 'bank_branch',
                'payment_instructions',
            ]);
        });
    }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * deposit = money in (the only kind recorded until now)
     * withdraw = money taken out
     * charge   = a bank fee/charge reconciled from the bank statement
     *
     * Default 'deposit' makes every existing row keep its current meaning —
     * everything recorded so far was implicitly a deposit.
     */
    public function up(): void
    {
        Schema::table('system_records', function (Blueprint $table) {
            $table->enum('type', ['deposit', 'withdraw', 'charge'])
                ->default('deposit')->after('system_property_id');

            $table->index(['bank_account_id', 'type', 'record_date']);
        });
    }

    public function down(): void
    {
        Schema::table('system_records', function (Blueprint $table) {
            $table->dropIndex(['bank_account_id', 'type', 'record_date']);
            $table->dropColumn('type');
        });
    }
};

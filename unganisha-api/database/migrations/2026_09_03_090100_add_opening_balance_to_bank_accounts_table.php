<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * The starting point for this account's balance statement — everything
     * before the earliest system_records row for it. Defaults to 0, same as
     * petty_cash_accounts.opening_balance.
     */
    public function up(): void
    {
        Schema::table('bank_accounts', function (Blueprint $table) {
            $table->decimal('opening_balance', 14, 2)->default(0)->after('account_number');
        });
    }

    public function down(): void
    {
        Schema::table('bank_accounts', function (Blueprint $table) {
            $table->dropColumn('opening_balance');
        });
    }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Without this, opening_balance could only mean "balance before any
     * system_records row exists" — if the account already has records
     * dated before whatever date the opening balance was actually taken
     * at, ReportController::bankBalanceStatement() would double-count
     * them (summing everything before the report's start date on top of
     * a number that may already include some of it). Null = old
     * behavior unchanged (treat as before all time).
     */
    public function up(): void
    {
        Schema::table('bank_accounts', function (Blueprint $table) {
            $table->date('opening_balance_date')->nullable()->after('opening_balance');
        });
    }

    public function down(): void
    {
        Schema::table('bank_accounts', function (Blueprint $table) {
            $table->dropColumn('opening_balance_date');
        });
    }
};

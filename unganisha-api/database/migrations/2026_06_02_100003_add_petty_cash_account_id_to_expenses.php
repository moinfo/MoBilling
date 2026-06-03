<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Tag an expense to a petty cash account so the same row counts in both
     * the Expenses ledger and the petty cash balance. NULL = not paid from
     * petty cash (the typical case).
     */
    public function up(): void
    {
        Schema::table('expenses', function (Blueprint $table) {
            $table->foreignUuid('petty_cash_account_id')->nullable()->after('sub_expense_category_id')
                ->constrained('petty_cash_accounts')->nullOnDelete();

            $table->index('petty_cash_account_id');
        });
    }

    public function down(): void
    {
        Schema::table('expenses', function (Blueprint $table) {
            $table->dropForeign(['petty_cash_account_id']);
            $table->dropIndex(['petty_cash_account_id']);
            $table->dropColumn('petty_cash_account_id');
        });
    }
};

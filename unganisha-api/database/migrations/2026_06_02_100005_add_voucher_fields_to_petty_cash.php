<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Voucher workflow: every petty cash disbursement (top-up, return, or
     * petty-cash-paid expense) generates a printable voucher with the names
     * of the giver and receiver. After printing and signing it physically,
     * the user uploads the scanned PDF back here as proof.
     *
     * Names are free-text (not FKs) because the receiver is often an outside
     * party — a vendor, a contractor, or a non-system user.
     */
    public function up(): void
    {
        Schema::table('petty_cash_transactions', function (Blueprint $table) {
            $table->string('given_by_name')->nullable()->after('notes');
            $table->string('received_by_name')->nullable()->after('given_by_name');
            $table->string('voucher_attachment_path')->nullable()->after('received_by_name');
        });

        Schema::table('expenses', function (Blueprint $table) {
            $table->string('given_by_name')->nullable()->after('petty_cash_account_id');
            $table->string('received_by_name')->nullable()->after('given_by_name');
            $table->string('voucher_attachment_path')->nullable()->after('attachment_path');
        });
    }

    public function down(): void
    {
        Schema::table('petty_cash_transactions', function (Blueprint $table) {
            $table->dropColumn(['given_by_name', 'received_by_name', 'voucher_attachment_path']);
        });

        Schema::table('expenses', function (Blueprint $table) {
            $table->dropColumn(['given_by_name', 'received_by_name', 'voucher_attachment_path']);
        });
    }
};

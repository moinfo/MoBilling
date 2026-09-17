<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Dual-control reconciliation: the person watching for the bank SMS and
     * the person checking the bank statement are usually different staff —
     * both must independently confirm before a deposit is considered
     * verified. Deliberately not in SystemRecord's $fillable — set only via
     * SystemRecordController::toggleSmsConfirmation()/
     * toggleStatementConfirmation() so there's always a who/when audit
     * trail, never a silent overwrite through the general edit form.
     */
    public function up(): void
    {
        Schema::table('system_records', function (Blueprint $table) {
            $table->timestamp('sms_confirmed_at')->nullable()->after('transaction_reference');
            $table->foreignUuid('sms_confirmed_by')->nullable()->after('sms_confirmed_at')->constrained('users')->nullOnDelete();
            $table->timestamp('statement_confirmed_at')->nullable()->after('sms_confirmed_by');
            $table->foreignUuid('statement_confirmed_by')->nullable()->after('statement_confirmed_at')->constrained('users')->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('system_records', function (Blueprint $table) {
            $table->dropForeign(['sms_confirmed_by']);
            $table->dropForeign(['statement_confirmed_by']);
            $table->dropColumn(['sms_confirmed_at', 'sms_confirmed_by', 'statement_confirmed_at', 'statement_confirmed_by']);
        });
    }
};

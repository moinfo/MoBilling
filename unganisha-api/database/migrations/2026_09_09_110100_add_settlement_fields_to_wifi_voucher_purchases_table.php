<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Only populated for platform_collected purchases. commission_amount/
     * net_amount are snapshotted at IPN-completion time from the
     * wifi_commission_percent PlatformSetting at that moment, so a later
     * rate change never rewrites historical ledger entries. Settlement
     * itself is a manual, audit-only record (mirrors Refund's non-wallet
     * shape) — no automated payout happens.
     */
    public function up(): void
    {
        Schema::table('wifi_voucher_purchases', function (Blueprint $table) {
            $table->decimal('commission_amount', 12, 2)->nullable()->after('amount');
            $table->decimal('net_amount', 12, 2)->nullable()->after('commission_amount');
            $table->timestamp('settled_at')->nullable()->after('completed_at');
            $table->enum('settlement_method', ['cash', 'bank', 'mpesa', 'pesapal', 'other'])->nullable()->after('settled_at');
            $table->string('settlement_reference')->nullable()->after('settlement_method');
            $table->text('settlement_notes')->nullable()->after('settlement_reference');
            $table->foreignUuid('settled_by')->nullable()->after('settlement_notes')
                ->constrained('users')->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('wifi_voucher_purchases', function (Blueprint $table) {
            $table->dropForeign(['settled_by']);
            $table->dropColumn([
                'commission_amount', 'net_amount', 'settled_at',
                'settlement_method', 'settlement_reference', 'settlement_notes', 'settled_by',
            ]);
        });
    }
};

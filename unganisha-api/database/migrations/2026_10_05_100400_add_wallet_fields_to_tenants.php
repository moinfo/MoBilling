<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * is_wallet_gated marks a tenant whose own auto-provisioning (hosting
 * ClientSubscriptionObserver, domain DocumentObserver) must be gated behind
 * TenantWalletGateService — set true only for tenants provisioned from a
 * ResellerApplication. Every other tenant (Moinfotech's own included) is
 * completely unaffected: the gate short-circuits immediately when this is
 * false. wallet_balance is the cached authoritative balance, mirroring
 * clients.credit_balance; tenant_wallet_transactions is the ledger/audit trail.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->boolean('is_wallet_gated')->default(false)->after('is_self_hosted');
            $table->decimal('wallet_balance', 14, 2)->default(0)->after('is_wallet_gated');
        });
    }

    public function down(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->dropColumn(['is_wallet_gated', 'wallet_balance']);
        });
    }
};

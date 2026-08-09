<?php

use App\Models\ProductService;
use App\Models\Tenant;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Domain reseller program: a client becomes a reseller by holding an active
 * subscription to the "Reseller Membership" product (annual fee — status is
 * derived from that subscription, never a separate stored flag, so the
 * existing recurring-billing/auto-suspend engine is the single source of
 * truth and reseller access is automatically revoked on non-payment).
 *
 * Resellers buy domains at `domain_tlds.reseller_price` (wholesale — what we
 * actually pay TZNIC) instead of the retail `register_price`, paid
 * immediately from their wallet balance (never invoiced-and-later-paid).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('domain_tlds', function (Blueprint $table) {
            $table->decimal('reseller_price', 12, 2)->nullable()->after('transfer_price');
        });

        // One "Reseller Membership" product per tenant — the SKU staff adds
        // to a client's subscriptions (via the existing subscription engine)
        // to grant reseller status. Price/cycle are editable afterwards like
        // any other product; 50,000/yr is just the starting default.
        foreach (Tenant::withoutGlobalScopes()->pluck('id') as $tenantId) {
            ProductService::withoutGlobalScopes()->firstOrCreate(
                ['tenant_id' => $tenantId, 'name' => 'Reseller Membership'],
                [
                    'type'           => 'service',
                    'category'       => 'Reseller',
                    'price'          => 50000,
                    'billing_cycle'  => 'yearly',
                    'tax_percent'    => 0,
                    'is_active'      => true,
                    'portal_visible' => false,
                    'description'    => "Annual domain reseller membership — buy .tz/gTLD domains at wholesale price, paid from your wallet.",
                ]
            );
        }
    }

    public function down(): void
    {
        Schema::table('domain_tlds', function (Blueprint $table) {
            $table->dropColumn('reseller_price');
        });
        ProductService::withoutGlobalScopes()->where('name', 'Reseller Membership')->delete();
    }
};

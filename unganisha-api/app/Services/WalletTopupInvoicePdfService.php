<?php

namespace App\Services;

use App\Models\PlatformSetting;
use App\Models\Tenant;
use App\Models\TenantWalletTopup;
use Barryvdh\DomPDF\Facade\Pdf;
use Illuminate\Support\Str;

/** Mirrors SubscriptionInvoicePdfService — a manual-payment invoice for a reseller tenant's wallet top-up. */
class WalletTopupInvoicePdfService
{
    public function generate(TenantWalletTopup $topup): \Barryvdh\DomPDF\PDF
    {
        $tenant = Tenant::withoutGlobalScopes()->find($topup->tenant_id);
        $bankDetails = PlatformSetting::getBankDetails();

        return Pdf::loadView('pdf.wallet-topup-invoice', [
            'topup' => $topup,
            'tenant' => $tenant,
            'reference' => static::reference($topup),
            'bankDetails' => $bankDetails,
        ])->setPaper('a4');
    }

    public static function reference(TenantWalletTopup $topup): string
    {
        return 'WALLET-' . Str::upper(substr(str_replace('-', '', $topup->id), -8));
    }
}

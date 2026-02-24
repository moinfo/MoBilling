<?php

namespace App\Services;

use App\Models\PlatformSetting;
use App\Models\TenantSubscription;
use Barryvdh\DomPDF\Facade\Pdf;

class SubscriptionInvoicePdfService
{
    public function generate(TenantSubscription $subscription): \Barryvdh\DomPDF\PDF
    {
        $subscription->load(['plan', 'user']);
        $tenant = $subscription->tenant()->withoutGlobalScopes()->first();
        $bankDetails = PlatformSetting::getBankDetails();

        return Pdf::loadView('pdf.subscription-invoice', [
            'subscription' => $subscription,
            'tenant' => $tenant,
            'plan' => $subscription->plan,
            'bankDetails' => $bankDetails,
        ])->setPaper('a4');
    }
}

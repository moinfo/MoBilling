<?php

namespace App\Services;

use App\Models\PlatformSetting;
use App\Models\SmsPurchase;
use Barryvdh\DomPDF\Facade\Pdf;

class SmsPurchasePdfService
{
    public function generateReceipt(SmsPurchase $purchase): \Barryvdh\DomPDF\PDF
    {
        $tenant = $purchase->tenant()->withoutGlobalScopes()->first();

        return Pdf::loadView('pdf.sms-receipt', [
            'purchase' => $purchase,
            'tenant' => $tenant,
        ])->setPaper('a4');
    }

    public function generateInvoice(SmsPurchase $purchase): \Barryvdh\DomPDF\PDF
    {
        $tenant = $purchase->tenant()->withoutGlobalScopes()->first();
        $bankDetails = PlatformSetting::getBankDetails();

        return Pdf::loadView('pdf.sms-invoice', [
            'purchase' => $purchase,
            'tenant' => $tenant,
            'bankDetails' => $bankDetails,
        ])->setPaper('a4');
    }
}

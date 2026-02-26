<?php

namespace App\Services;

use App\Models\Document;
use App\Models\PaymentIn;
use Barryvdh\DomPDF\Facade\Pdf;

class PdfService
{
    public function generate(Document $document)
    {
        $document->load('items', 'client', 'tenant');

        $tenant = $document->tenant;
        $paymentMethods = $tenant->payment_methods ?? [];

        return Pdf::loadView('pdf.document', [
            'document' => $document,
            'tenant' => $tenant,
            'client' => $document->client,
            'items' => $document->items,
            'paymentMethods' => $paymentMethods,
        ])->setPaper('a4');
    }

    public function generateReceipt(PaymentIn $payment, Document $document)
    {
        $document->load('client', 'tenant');

        $totalPaid = $document->payments()->sum('amount');
        $balanceDue = $document->total - $totalPaid;

        return Pdf::loadView('pdf.receipt', [
            'document' => $document,
            'payment' => $payment,
            'tenant' => $document->tenant,
            'client' => $document->client,
            'totalPaid' => $totalPaid,
            'balanceDue' => $balanceDue,
        ])->setPaper('a4');
    }
}

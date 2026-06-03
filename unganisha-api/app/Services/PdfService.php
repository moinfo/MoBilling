<?php

namespace App\Services;

use App\Models\Document;
use App\Models\Expense;
use App\Models\PaymentIn;
use App\Models\PettyCashTransaction;
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

    /**
     * Generate a printable petty-cash voucher from either an Expense (paid
     * from petty cash) or a PettyCashTransaction (top-up / return). The
     * Blade template consumes a normalized payload so it doesn't care which.
     */
    public function generatePettyCashVoucher($source)
    {
        if ($source instanceof Expense) {
            $source->load('tenant', 'subCategory.category');
            $tenant = $source->tenant;
            if (!$tenant) {
                throw new \RuntimeException("Cannot render voucher: tenant missing for source {$source->id}");
            }
            $payload = [
                'voucher_number' => 'PCV-' . strtoupper(substr($source->id, 0, 8)),
                'title' => 'Petty Cash Voucher',
                'date' => $source->expense_date,
                'amount' => (float) $source->amount,
                'purpose' => $source->description,
                'category' => $source->subCategory?->category?->name,
                'sub_category' => $source->subCategory?->name,
                'given_by_name' => $source->given_by_name,
                'received_by_name' => $source->received_by_name,
                'reference' => $source->reference,
                'notes' => $source->notes,
            ];
        } elseif ($source instanceof PettyCashTransaction) {
            $source->load('tenant');
            $tenant = $source->tenant;
            if (!$tenant) {
                throw new \RuntimeException("Cannot render voucher: tenant missing for source {$source->id}");
            }
            $title = match ($source->type) {
                'top_up' => 'Petty Cash Top-Up Voucher',
                'return' => 'Petty Cash Return Voucher',
                'adjustment_in' => 'Petty Cash Adjustment (Gain) Voucher',
                'adjustment_out' => 'Petty Cash Adjustment (Loss) Voucher',
                default => 'Petty Cash Voucher',
            };
            $payload = [
                'voucher_number' => 'PCV-' . strtoupper(substr($source->id, 0, 8)),
                'title' => $title,
                'date' => $source->transaction_date,
                'amount' => (float) $source->amount,
                'purpose' => $source->notes ?: $title,
                'category' => null,
                'sub_category' => null,
                'given_by_name' => $source->given_by_name,
                'received_by_name' => $source->received_by_name,
                'reference' => $source->reference,
                'notes' => $source->notes,
            ];
        } else {
            throw new \InvalidArgumentException('generatePettyCashVoucher requires an Expense or PettyCashTransaction.');
        }

        return Pdf::loadView('pdf.petty_cash_voucher', [
            'tenant' => $tenant,
            'voucher' => $payload,
        ])->setPaper('a5');
    }
}

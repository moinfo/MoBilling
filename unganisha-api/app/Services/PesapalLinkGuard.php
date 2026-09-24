<?php

namespace App\Services;

use App\Models\Document;
use App\Models\PesapalInvoicePayment;

/**
 * Guards for creating online-payment links: an invoice must still be
 * payable, and a fresh identical pending link is reused rather than
 * stacking a second one (two links for one invoice = double-pay risk).
 */
class PesapalLinkGuard
{
    public const REUSE_MINUTES = 30;

    /** Re-load the invoice and return it only when it can still take a payment. */
    public function payable(Document $document): ?Document
    {
        $fresh = Document::withoutGlobalScopes()->find($document->id);
        if (!$fresh || $fresh->type !== 'invoice') {
            return null;
        }
        if (!in_array($fresh->status, ['sent', 'overdue', 'partial'], true)) {
            return null;
        }
        if ((float) $fresh->balance_due <= 0) {
            return null;
        }
        return $fresh;
    }

    /** An open link for the same document + amount created in the last 30 minutes. */
    public function reusablePending(Document $document, float $amount): ?PesapalInvoicePayment
    {
        return PesapalInvoicePayment::where('document_id', $document->id)
            ->where('status', 'pending')
            ->whereNull('completed_at')
            ->whereNotNull('pesapal_redirect_url')
            ->where('created_at', '>=', now()->subMinutes(self::REUSE_MINUTES))
            ->get()
            ->first(fn ($p) => abs((float) $p->amount - $amount) < 0.005);
    }
}

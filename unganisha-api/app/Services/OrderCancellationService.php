<?php

namespace App\Services;

use App\Models\ClientSubscription;
use App\Models\Document;
use App\Models\Domain;
use App\Models\RecurringInvoiceLog;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Cancel an UNPAID order (WhatsApp-created invoice + its pending domain /
 * subscription). Never touches a paid invoice or one with any payment on it.
 * The coupon use is released by DocumentObserver when the status flips to
 * cancelled, so every cancel path shares that behaviour.
 */
class OrderCancellationService
{
    /** Marker written into the notes of every WhatsApp-created order invoice. */
    public const WHATSAPP_MARKER = '(WhatsApp order)';

    public function isWhatsappOrder(Document $doc): bool
    {
        return str_contains((string) $doc->notes, self::WHATSAPP_MARKER);
    }

    /** Can this invoice still be cancelled as an unpaid order? */
    public function cancellable(Document $doc): bool
    {
        return $doc->type === 'invoice'
            && in_array($doc->status, ['sent', 'overdue', 'draft'], true)
            && (float) $doc->paid_amount <= 0
            && !\App\Models\PesapalInvoicePayment::where('document_id', $doc->id)->where('status', 'completed')->exists();
    }

    /** @return bool true when the invoice was cancelled by this call */
    public function cancelUnpaidOrder(Document $doc, string $reason = 'Order cancelled'): bool
    {
        return DB::transaction(function () use ($doc, $reason) {
            $locked = Document::withoutGlobalScopes()->whereKey($doc->id)->lockForUpdate()->first();
            if (!$locked || !$this->cancellable($locked)) {
                return false;
            }

            $locked->update([
                'status' => 'cancelled', // observer releases the coupon use
                'notes'  => trim(($locked->notes ? $locked->notes . "\n" : '') . $reason . ' ' . now()->toDateTimeString()),
            ]);

            $this->cancelLinkedDomains($locked);
            $this->cancelPendingSubscriptions($locked);

            Log::info('Unpaid order cancelled', ['document_id' => $locked->id, 'reason' => $reason]);
            return true;
        });
    }

    /** Pending register/transfer domain -> cancelled; a renewal only loses its pending flag. */
    public function cancelLinkedDomains(Document $document): void
    {
        $domains = Domain::withoutGlobalScopes()
            ->where(fn ($q) => $q
                ->where('meta->order_document_id', $document->id)
                ->orWhere('meta->renewal_document_id', $document->id))
            ->whereNotNull('meta->pending_action')
            ->get();

        foreach ($domains as $domain) {
            $meta = $domain->meta ?? [];
            $wasRegisterOrTransfer = in_array($meta['pending_action'] ?? null, ['register', 'transfer'], true);
            unset($meta['pending_action'], $meta['pending_years']);

            $domain->update([
                'status' => ($wasRegisterOrTransfer && $domain->status === 'pending') ? 'cancelled' : $domain->status,
                'meta' => $meta,
            ]);
        }
    }

    /** A subscription still 'pending' whose only invoice is this one is cancelled. */
    public function cancelPendingSubscriptions(Document $document): void
    {
        $subIds = RecurringInvoiceLog::withoutGlobalScopes()->where('document_id', $document->id)
            ->whereNotNull('client_subscription_id')->pluck('client_subscription_id');

        foreach (ClientSubscription::withoutGlobalScopes()->whereIn('id', $subIds)->where('status', 'pending')->get() as $sub) {
            $otherPaid = RecurringInvoiceLog::withoutGlobalScopes()
                ->where('client_subscription_id', $sub->id)->where('document_id', '!=', $document->id)
                ->whereHas('document', fn ($q) => $q->where('status', 'paid'))->exists();
            if (!$otherPaid) {
                $sub->update(['status' => 'cancelled']);
            }
        }
    }
}

<?php

namespace App\Observers;

use App\Jobs\Domains\RegisterDomainJob;
use App\Jobs\Domains\RenewDomainJob;
use App\Jobs\Domains\TransferDomainJob;
use App\Models\Document;
use App\Models\Domain;

/**
 * When an invoice becomes paid, fulfil any domain order attached to it
 * (docs/IMPLEMENTATION_PLAN.md §B3). Single hook point for every payment
 * path: manual PaymentIn recording, Pesapal IPN, portal payment.
 */
class DocumentObserver
{
    public function updated(Document $document): void
    {
        if (!$document->wasChanged('status') || $document->status !== 'paid') {
            return;
        }

        $domains = Domain::withoutGlobalScopes()
            ->where('tenant_id', $document->tenant_id)
            ->where(fn ($q) => $q
                ->where('meta->order_document_id', $document->id)
                ->orWhere('meta->renewal_document_id', $document->id))
            ->whereNotNull('meta->pending_action')
            ->get();

        foreach ($domains as $domain) {
            // Unmanaged domains (gTLDs — no registrar driver yet): keep the paid
            // order flagged for MANUAL fulfilment at the upstream registrar
            // instead of firing EPP that would fail and mark the domain failed.
            if ($domain->meta['unmanaged'] ?? false) {
                \Illuminate\Support\Facades\Log::info(
                    "Domain order paid but unmanaged (manual fulfilment needed): {$domain->name}"
                );
                continue;
            }

            match ($domain->meta['pending_action'] ?? null) {
                'register' => RegisterDomainJob::dispatch($domain),
                'transfer' => TransferDomainJob::dispatch($domain),
                'renew'    => RenewDomainJob::dispatch($domain),
                default    => null,
            };
        }
    }
}

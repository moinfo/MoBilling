<?php

namespace App\Services\Registrar;

use App\Models\Document;
use App\Models\Domain;
use App\Models\DomainTld;
use App\Services\DocumentNumberService;
use Illuminate\Support\Facades\DB;

/**
 * Creates domain renewal invoices — shared by the manual renew endpoint and
 * the domains:process-renewals command. The registry renewal itself only
 * fires when the invoice is paid (DocumentObserver -> RenewDomainJob).
 */
class DomainBillingService
{
    public function createRenewalInvoice(Domain $domain, int $years, ?string $createdBy = null): Document
    {
        $tld = strtolower(explode('.', $domain->name, 2)[1] ?? '');
        $pricing = DomainTld::priceFor($domain->tenant_id, $tld);

        if (!$pricing) {
            throw new \RuntimeException("No pricing configured for .{$tld}");
        }

        $total = round((float) $pricing->renew_price * $years, 2);

        return DB::transaction(function () use ($domain, $years, $total, $pricing, $createdBy) {
            $document = Document::withoutGlobalScopes()->create([
                'tenant_id'       => $domain->tenant_id,
                'client_id'       => $domain->client_id,
                'type'            => 'invoice',
                'document_number' => app(DocumentNumberService::class)->generate('invoice', $domain->tenant_id),
                'date'            => now()->toDateString(),
                'due_date'        => $domain->expires_at?->isFuture()
                    ? $domain->expires_at->toDateString()
                    : now()->addDays(7)->toDateString(),
                'subtotal'        => $total,
                'discount_amount' => 0,
                'tax_amount'      => 0,
                'total'           => $total,
                'status'          => 'sent',
                'notes'           => "Domain renewal: {$domain->name} ({$years} year(s))",
                'created_by'      => $createdBy,
            ]);

            $document->items()->create([
                'item_type'   => 'service',
                'description' => "Renew domain {$domain->name} — {$years} year(s)",
                'quantity'    => $years,
                'price'       => $pricing->renew_price,
                'tax_percent' => 0,
                'tax_amount'  => 0,
                'total'       => $total,
            ]);

            $domain->update(['meta' => array_merge($domain->meta ?? [], [
                'pending_action'      => 'renew',
                'pending_years'       => $years,
                'renewal_document_id' => $document->id,
            ])]);

            return $document;
        });
    }
}

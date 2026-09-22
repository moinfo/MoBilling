<?php

namespace App\Services\Hosting;

use App\Models\ClientSubscription;
use App\Models\Document;
use App\Models\Domain;
use App\Models\HostingAccount;
use App\Models\RecurringInvoiceLog;
use App\Services\RecurringInvoiceService;

/**
 * Resolves and bills whatever a hosting account's domain owes — the hosting
 * plan, its domain registration, or both — as one bundled invoice. Shared by
 * the staff-facing "Generate Invoice" action (HostingAccountController) and
 * the WhatsApp self-service renewal webhook, so there is exactly one place
 * that creates this kind of invoice and exactly one place that wires the
 * result up to actually renew the domain at the registry.
 */
class RenewalBundleService
{
    /**
     * The hosting account's real hosting-PLAN subscription — not just
     * $hostingAccount->subscription, which has repeatedly been found
     * pointing at the wrong subscription for this domain (a Backup add-on,
     * a Domain Registration, or a stale cancelled one — see
     * PlanChangeService's own fallback for the first instance of this).
     * Prefers the active "Web Hosting" subscription matched by domain
     * name; falls back to the direct relation if none matches.
     */
    public function hostingPlanSubscription(HostingAccount $hostingAccount): ?ClientSubscription
    {
        $byDomain = ClientSubscription::withoutGlobalScopes()
            ->whereNull('deleted_at')
            ->where('tenant_id', $hostingAccount->tenant_id)
            ->where('label', $hostingAccount->domain)
            ->where('status', 'active')
            ->whereHas('productService', fn ($q) => $q->where('category', 'Web Hosting'))
            ->with('productService')
            ->first();

        return $byDomain ?? $hostingAccount->subscription;
    }

    /**
     * This domain's own registration subscription, if any — "hosting" for a
     * client is the hosting plan AND the domain together, so the manual
     * invoice action bundles both rather than leaving the domain renewal
     * out (matches how the automated job groups everything due for a
     * client into one invoice). Not required — many domains are registered
     * elsewhere — so this returns null rather than erroring when absent.
     * Deliberately not status-filtered to 'active': a lapsed domain
     * subscription is exactly the case staff need to manually re-invoice.
     */
    public function domainSubscription(HostingAccount $hostingAccount): ?ClientSubscription
    {
        return ClientSubscription::withoutGlobalScopes()
            ->whereNull('deleted_at')
            ->where('tenant_id', $hostingAccount->tenant_id)
            ->where('label', $hostingAccount->domain)
            ->where('status', '!=', 'cancelled')
            ->whereHas('productService', fn ($q) => $q->where('category', 'Domain'))
            ->with('productService')
            ->latest('start_date')
            ->first();
    }

    /** @return array{candidates: ClientSubscription[], billable: ClientSubscription[]} */
    public function billableSubscriptions(HostingAccount $hostingAccount): array
    {
        $candidates = array_values(array_filter([
            $this->hostingPlanSubscription($hostingAccount),
            $this->domainSubscription($hostingAccount),
        ]));

        // Never re-bundle a subscription that already has a real invoice —
        // hosting and domain are invoiced independently, so one having a
        // current invoice must not block (or duplicate-charge) the other.
        $billable = array_values(array_filter($candidates, fn ($sub) => !$this->hasCurrentInvoice($sub)));

        return compact('candidates', 'billable');
    }

    /** Whether $sub already has an invoice that represents a real charge (not draft/cancelled). */
    public function hasCurrentInvoice(ClientSubscription $sub): bool
    {
        return RecurringInvoiceLog::withoutGlobalScopes()
            ->where('client_subscription_id', $sub->id)
            ->whereHas('document', fn ($q) => $q->whereIn('status', ['sent', 'overdue', 'partial', 'paid']))
            ->exists();
    }

    /** Price preview for a manual "generate invoice" action — computes, doesn't create anything. */
    public function preview(HostingAccount $hostingAccount): array
    {
        ['candidates' => $candidates, 'billable' => $billable] = $this->billableSubscriptions($hostingAccount);
        if (empty($candidates)) {
            throw new \RuntimeException('No hosting-plan or domain subscription found for this domain.');
        }
        if (empty($billable)) {
            throw new \RuntimeException('Everything for this domain already has a current invoice — nothing left to bill.');
        }

        $preview = app(RecurringInvoiceService::class)->previewForSubscriptions($billable);

        return $preview + [
            'product_name' => implode(' + ', array_map(fn ($s) => $s->productService->name, $billable)),
            'client_name'  => $billable[0]->client()->withoutGlobalScopes()->value('name'),
        ];
    }

    /** Generates the renewal invoice this domain is missing — bundles the domain renewal in too, if it has one. */
    public function generate(HostingAccount $hostingAccount): Document
    {
        ['candidates' => $candidates, 'billable' => $billable] = $this->billableSubscriptions($hostingAccount);
        if (empty($candidates)) {
            throw new \RuntimeException('No hosting-plan or domain subscription found for this domain.');
        }
        if (empty($billable)) {
            throw new \RuntimeException('Everything for this domain already has a current invoice — nothing left to bill.');
        }

        $document = app(RecurringInvoiceService::class)->generateForSubscriptions($billable);

        $this->markDomainRenewalPending($document, $billable);

        return $document;
    }

    /**
     * A domain-registration subscription in the bundle doesn't, by itself,
     * make the paid invoice actually renew the domain at the registry —
     * that only happens via DocumentObserver, which looks for a Domain row
     * carrying meta->renewal_document_id + pending_action, exactly as
     * DomainBillingService::createRenewalInvoice stamps it. This bundle
     * path bills a ClientSubscription, not a Domain, so without this the
     * client pays and the domain silently stays expired at the registry
     * (found live on manya.co.tz: invoice paid, subscription "renewed",
     * registry never touched).
     */
    private function markDomainRenewalPending(Document $document, array $billable): void
    {
        foreach ($billable as $sub) {
            if ($sub->productService?->category !== 'Domain') {
                continue;
            }

            $domain = Domain::withoutGlobalScopes()
                ->where('tenant_id', $sub->tenant_id)
                ->where('client_id', $sub->client_id)
                ->where('name', $sub->label)
                ->first();

            if (!$domain) {
                continue;
            }

            $domain->update(['meta' => array_merge($domain->meta ?? [], [
                'pending_action'      => 'renew',
                'pending_years'       => max(1, (int) $sub->quantity),
                'renewal_document_id' => $document->id,
            ])]);
        }
    }
}

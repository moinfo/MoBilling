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

        // Add-funds top-ups: deposit the credit once the invoice is paid.
        $pendingTopups = \App\Models\ClientCredit::withoutGlobalScopes()
            ->where('tenant_id', $document->tenant_id)
            ->where('type', 'topup_pending')
            ->where('document_id', $document->id)
            ->get();

        foreach ($pendingTopups as $topup) {
            $topup->update(['type' => 'topup_consumed']);
            $client = \App\Models\Client::withoutGlobalScopes()->find($topup->client_id);
            if ($client) {
                app(\App\Services\CreditService::class)->adjust(
                    $client, (float) $topup->amount, 'deposit',
                    "Add funds — invoice {$document->document_number}", $document->id
                );
            }
        }

        // Plan upgrades: apply the pending change once its invoice is paid.
        $pendingChanges = \App\Models\ClientSubscription::withoutGlobalScopes()
            ->where('tenant_id', $document->tenant_id)
            ->where('metadata->pending_plan_change->document_id', $document->id)
            ->get();

        foreach ($pendingChanges as $sub) {
            $newProduct = \App\Models\ProductService::withoutGlobalScopes()
                ->find($sub->metadata['pending_plan_change']['product_service_id'] ?? null);
            if ($newProduct) {
                app(\App\Services\Hosting\PlanChangeService::class)->apply($sub, $newProduct);
            }
        }

        // Paid product add-ons: attach ordered add-ons to the service once its
        // invoice is paid, snapshotting name/price/cycle so later catalog edits
        // don't change what an existing service renews at.
        $pendingAddonSubs = \App\Models\ClientSubscription::withoutGlobalScopes()
            ->where('tenant_id', $document->tenant_id)
            ->where('metadata->pending_addons->document_id', $document->id)
            ->get();

        foreach ($pendingAddonSubs as $sub) {
            $addonIds = $sub->metadata['pending_addons']['addon_ids'] ?? [];
            $addons = \App\Models\ProductAddon::withoutGlobalScopes()->withTrashed()
                ->where('tenant_id', $sub->tenant_id)
                ->whereIn('id', $addonIds)
                ->get();

            foreach ($addons as $addon) {
                \App\Models\SubscriptionAddon::withoutGlobalScopes()->firstOrCreate(
                    [
                        'client_subscription_id' => $sub->id,
                        'product_addon_id'       => $addon->id,
                    ],
                    [
                        'tenant_id'     => $sub->tenant_id,
                        'name'          => $addon->name,
                        'price'         => $addon->price,
                        'billing_cycle' => $addon->billing_cycle,
                        'tax_percent'   => $addon->tax_percent,
                        'status'        => 'active',
                    ]
                );
            }

            $meta = $sub->metadata ?? [];
            unset($meta['pending_addons']);
            $sub->update(['metadata' => $meta]);
        }

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

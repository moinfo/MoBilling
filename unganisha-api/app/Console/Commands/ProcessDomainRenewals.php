<?php

namespace App\Console\Commands;

use App\Models\CronLog;
use App\Models\Document;
use App\Models\Domain;
use App\Models\Tenant;
use App\Notifications\InvoiceSentNotification;
use App\Services\Registrar\DomainBillingService;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Log;

/**
 * Generate renewal invoices for domains expiring within the window — for
 * auto-renew domains, also pay them from the client's credit wallet when
 * the balance covers the full amount (auto-renew only completes while the
 * wallet is funded). Manual-renew domains get the same invoice + email but
 * are never auto-paid — the client was relying solely on
 * SendDomainExpiryReminders' "reply 1 on WhatsApp" self-service flow (or
 * staff creating one by hand) to ever get an actual invoice, which left
 * domains expiring with nothing concrete for the client to pay. The
 * registry renewal itself fires when the invoice is paid (DocumentObserver).
 */
class ProcessDomainRenewals extends Command
{
    protected $signature = 'domains:process-renewals {--window=45 : Days before expiry to invoice}';
    protected $description = 'Create renewal invoices for domains nearing expiry (auto-renew ones are also paid from wallet credit)';

    public function handle(DomainBillingService $billing): int
    {
        $startedAt = now();
        $window = (int) $this->option('window');
        $created = 0;
        $skipped = 0;
        $failed = 0;
        $walletPaid = 0;

        $domains = Domain::withoutGlobalScopes()
            ->with('client')
            // Parallel mode: WHMCS invoices renewals of imported domains.
            ->when(config('whmcs.parallel_mode'), fn ($q) => $q->whereNull('legacy_id'))
            ->whereIn('status', ['active', 'expired'])
            ->whereNotNull('expires_at')
            // Symmetric floor: a domain expired well past the window is
            // almost certainly outside the registry's redemption grace
            // period already (lost or needs a manual redeem, not a normal
            // renewal) — don't invoice/email a client for one of those.
            ->whereBetween('expires_at', [now()->subDays($window), now()->addDays($window)])
            ->get();

        foreach ($domains as $domain) {
            // Tenant must be in good standing.
            $tenant = Tenant::find($domain->tenant_id);
            if (!$tenant || !$tenant->hasAccess()) {
                $skipped++;
                continue;
            }

            // An open renewal invoice already exists: retry the wallet each day
            // for auto-renew domains (the client may have topped up since),
            // otherwise leave it unpaid — there's nothing more to do until the
            // client pays, so don't re-create or re-email it every run.
            $openInvoiceId = $domain->meta['renewal_document_id'] ?? null;
            if ($openInvoiceId) {
                $open = Document::withoutGlobalScopes()->find($openInvoiceId);
                if ($open && !in_array($open->status, ['paid', 'cancelled'])) {
                    if ($domain->auto_renew && $this->payFromWallet($domain, $open)) {
                        $walletPaid++;
                        $this->info("Wallet-paid open renewal: {$domain->name} -> {$open->document_number}");
                    } else {
                        $skipped++;
                    }
                    continue;
                }
            }

            try {
                $document = $billing->createRenewalInvoice($domain, 1);
                $created++;

                if ($domain->auto_renew && $this->payFromWallet($domain, $document)) {
                    $walletPaid++;
                    $this->info("Auto-renewed from wallet: {$domain->name} -> {$document->document_number}");
                    continue; // paid — no "please pay" email
                }

                // Not auto-renew, or wallet can't cover it: email the invoice
                // so the client has something concrete to pay (or top up
                // their wallet) themselves.
                if ($domain->client?->email) {
                    try {
                        $domain->client->notify(new InvoiceSentNotification($document));
                    } catch (\Throwable $e) {
                        Log::warning("Renewal invoice email failed for {$domain->name}: {$e->getMessage()}");
                    }
                }
                $this->info(($domain->auto_renew ? "Invoiced (wallet insufficient): " : "Invoiced (manual renew): ") . "{$domain->name} -> {$document->document_number}");
            } catch (\Throwable $e) {
                $failed++;
                $this->warn("Failed {$domain->name}: {$e->getMessage()}");
            }
        }

        $this->info("Done. Created {$created}, wallet-paid {$walletPaid}, skipped {$skipped}, failed {$failed}");

        CronLog::create([
            'tenant_id'   => null,
            'command'     => $this->signature,
            'description' => "Created {$created} domain renewal invoices ({$walletPaid} paid from wallet, {$skipped} skipped, {$failed} failed)",
            'results'     => compact('created', 'walletPaid', 'skipped', 'failed'),
            'status'      => $failed > 0 ? 'failed' : 'success',
            'started_at'  => $startedAt,
            'finished_at' => now(),
        ]);

        return self::SUCCESS;
    }

    /**
     * Pay the renewal invoice from the client's credit wallet — only when the
     * balance covers the FULL outstanding amount (a partial payment would
     * drain the wallet without triggering the registry renewal).
     */
    private function payFromWallet(Domain $domain, Document $document): bool
    {
        $client = \App\Models\Client::withoutGlobalScopes()->find($domain->client_id);
        if (!$client) {
            return false;
        }

        $due = (float) $document->total - (float) $document->payments()->sum('amount');
        if ($due <= 0) {
            return true; // already settled
        }
        if ((float) $client->credit_balance < $due) {
            return false;
        }

        try {
            app(\App\Services\CreditService::class)->applyToInvoice($client, $document, $due);
            return true;
        } catch (\Throwable $e) {
            Log::warning("Wallet auto-renew payment failed for {$domain->name}: {$e->getMessage()}");
            return false;
        }
    }
}

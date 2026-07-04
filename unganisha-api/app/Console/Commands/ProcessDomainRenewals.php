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
 * Generate renewal invoices for auto-renew domains expiring within the window,
 * then pay them from the client's credit wallet when the balance covers the
 * full amount — auto-renew only completes while the wallet is funded. The
 * registry renewal itself fires when the invoice is paid (DocumentObserver).
 */
class ProcessDomainRenewals extends Command
{
    protected $signature = 'domains:process-renewals {--window=45 : Days before expiry to invoice}';
    protected $description = 'Create renewal invoices for auto-renew domains nearing expiry and pay them from wallet credit';

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
            ->where('status', 'active')
            ->where('auto_renew', true)
            ->whereNotNull('expires_at')
            ->whereDate('expires_at', '<=', now()->addDays($window))
            ->get();

        foreach ($domains as $domain) {
            // Tenant must be in good standing.
            $tenant = Tenant::find($domain->tenant_id);
            if (!$tenant || !$tenant->hasAccess()) {
                $skipped++;
                continue;
            }

            // An open renewal invoice already exists: retry the wallet each day
            // (the client may have topped up since), otherwise leave it unpaid.
            $openInvoiceId = $domain->meta['renewal_document_id'] ?? null;
            if ($openInvoiceId) {
                $open = Document::withoutGlobalScopes()->find($openInvoiceId);
                if ($open && !in_array($open->status, ['paid', 'cancelled'])) {
                    if ($this->payFromWallet($domain, $open)) {
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

                if ($this->payFromWallet($domain, $document)) {
                    $walletPaid++;
                    $this->info("Auto-renewed from wallet: {$domain->name} -> {$document->document_number}");
                    continue; // paid — no "please pay" email
                }

                // Wallet can't cover it: email the invoice so the client can
                // pay it (or top up) themselves.
                if ($domain->client?->email) {
                    try {
                        $domain->client->notify(new InvoiceSentNotification($document));
                    } catch (\Throwable $e) {
                        Log::warning("Renewal invoice email failed for {$domain->name}: {$e->getMessage()}");
                    }
                }
                $this->info("Invoiced (wallet insufficient): {$domain->name} -> {$document->document_number}");
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

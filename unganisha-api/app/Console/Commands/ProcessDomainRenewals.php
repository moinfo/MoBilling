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
 * Generate renewal invoices for auto-renew domains expiring within the window.
 * The registry renewal itself fires when the invoice is paid (DocumentObserver).
 */
class ProcessDomainRenewals extends Command
{
    protected $signature = 'domains:process-renewals {--window=45 : Days before expiry to invoice}';
    protected $description = 'Create renewal invoices for auto-renew domains nearing expiry';

    public function handle(DomainBillingService $billing): int
    {
        $startedAt = now();
        $window = (int) $this->option('window');
        $created = 0;
        $skipped = 0;
        $failed = 0;

        $domains = Domain::withoutGlobalScopes()
            ->with('client')
            ->where('status', 'active')
            ->where('auto_renew', true)
            ->whereNotNull('expires_at')
            ->whereDate('expires_at', '<=', now()->addDays($window))
            ->get();

        foreach ($domains as $domain) {
            // Skip when an open renewal invoice already exists for this domain.
            $openInvoiceId = $domain->meta['renewal_document_id'] ?? null;
            if ($openInvoiceId) {
                $open = Document::withoutGlobalScopes()->find($openInvoiceId);
                if ($open && !in_array($open->status, ['paid', 'cancelled'])) {
                    $skipped++;
                    continue;
                }
            }
            // Tenant must be in good standing.
            $tenant = Tenant::find($domain->tenant_id);
            if (!$tenant || !$tenant->hasAccess()) {
                $skipped++;
                continue;
            }

            try {
                $document = $billing->createRenewalInvoice($domain, 1);
                $created++;

                if ($domain->client?->email) {
                    try {
                        $domain->client->notify(new InvoiceSentNotification($document));
                    } catch (\Throwable $e) {
                        Log::warning("Renewal invoice email failed for {$domain->name}: {$e->getMessage()}");
                    }
                }
                $this->info("Invoiced: {$domain->name} -> {$document->document_number}");
            } catch (\Throwable $e) {
                $failed++;
                $this->warn("Failed {$domain->name}: {$e->getMessage()}");
            }
        }

        $this->info("Done. Created {$created}, skipped {$skipped}, failed {$failed}");

        CronLog::create([
            'tenant_id'   => null,
            'command'     => $this->signature,
            'description' => "Created {$created} domain renewal invoices ({$skipped} skipped, {$failed} failed)",
            'results'     => compact('created', 'skipped', 'failed'),
            'status'      => $failed > 0 ? 'failed' : 'success',
            'started_at'  => $startedAt,
            'finished_at' => now(),
        ]);

        return self::SUCCESS;
    }
}

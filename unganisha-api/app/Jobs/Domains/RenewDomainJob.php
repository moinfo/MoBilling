<?php

namespace App\Jobs\Domains;

use App\Models\Domain;
use App\Notifications\DomainRenewedNotification;
use Illuminate\Support\Facades\Log;

class RenewDomainJob extends BaseDomainJob
{
    public function __construct(public Domain $domain) {}

    public function handle(): void
    {
        $domain = $this->domain->fresh('client');

        if (!$domain || ($domain->meta['pending_action'] ?? null) !== 'renew') {
            return;
        }

        $years = (int) ($domain->meta['pending_years'] ?? 1);

        $this->guard($domain, function () use ($domain, $years) {
            $this->driver($domain)->renew($domain->name, $years);

            if ($domain->status === 'expired') {
                $domain->update(['status' => 'active']);
            }
            $this->clearPending($domain);
            $this->syncFromRegistry($domain);

            if ($domain->client?->email) {
                try {
                    $domain->client->notify(new DomainRenewedNotification($domain->fresh()));
                } catch (\Throwable $e) {
                    Log::warning("Domain renewed email failed for {$domain->name}: {$e->getMessage()}");
                }
            }
        });
    }
}

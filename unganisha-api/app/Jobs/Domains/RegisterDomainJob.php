<?php

namespace App\Jobs\Domains;

use App\Models\Domain;
use App\Notifications\DomainRegisteredNotification;
use Illuminate\Support\Facades\Log;

class RegisterDomainJob extends BaseDomainJob
{
    public function __construct(public Domain $domain) {}

    public function handle(): void
    {
        $domain = $this->domain->fresh('client');

        // Idempotency guard: exact pending state only — a double-fire is a no-op.
        if (!$domain || $domain->status !== 'pending' || ($domain->meta['pending_action'] ?? null) !== 'register') {
            return;
        }

        $years = (int) ($domain->meta['pending_years'] ?? 1);

        $this->guard($domain, function () use ($domain, $years) {
            $this->driver($domain)->register($domain->name, $years);

            $domain->update(['status' => 'active']);
            $this->clearPending($domain);
            $this->syncFromRegistry($domain);

            // Point the fresh domain at the tenant's hosting nameservers so it
            // resolves immediately. Best-effort — staff can change them later.
            if (!$domain->fresh()->nsset_handle) {
                $ns = \App\Models\Server::withoutGlobalScopes()
                    ->where('tenant_id', $domain->tenant_id)
                    ->where('is_active', true)
                    ->whereNotNull('nameservers')
                    ->value('nameservers')
                    ?: config('hosting.default_nameservers', []);
                $ns = is_string($ns) ? json_decode($ns, true) : $ns;
                if ($ns) {
                    try {
                        app(\App\Services\Registrar\NameserverService::class)
                            ->update($domain->fresh(), (array) $ns, ['auto' => 'post_register']);
                    } catch (\Throwable $e) {
                        Log::warning("Default NS attach failed for {$domain->name}: {$e->getMessage()}");
                    }
                }
            }

            if ($domain->client?->email) {
                try {
                    $domain->client->notify(new DomainRegisteredNotification($domain->fresh()));
                } catch (\Throwable $e) {
                    Log::warning("Domain registered email failed for {$domain->name}: {$e->getMessage()}");
                }
            }
        });
    }
}

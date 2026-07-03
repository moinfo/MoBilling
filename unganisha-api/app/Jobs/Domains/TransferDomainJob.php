<?php

namespace App\Jobs\Domains;

use App\Models\Domain;

class TransferDomainJob extends BaseDomainJob
{
    public function __construct(public Domain $domain) {}

    public function handle(): void
    {
        $domain = $this->domain->fresh();

        if (!$domain || $domain->status !== 'pending' || ($domain->meta['pending_action'] ?? null) !== 'transfer') {
            return;
        }

        $this->guard($domain, function () use ($domain) {
            $this->driver($domain)->transferIn($domain->name, $domain->epp_auth_info ?? '');

            // Registry transfers complete asynchronously — domains:sync flips the
            // status to active once the registry shows us as the sponsoring registrar.
            $domain->update(['meta' => array_merge($domain->meta ?? [], [
                'transfer_requested_at' => now()->toIso8601String(),
            ])]);
            $this->clearPending($domain);
        });
    }
}

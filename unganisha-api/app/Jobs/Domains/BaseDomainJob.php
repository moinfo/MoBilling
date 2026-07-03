<?php

namespace App\Jobs\Domains;

use App\Models\Domain;
use App\Services\Registrar\DomainRegistrarManager;
use App\Contracts\RegistrarDriver;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\Log;

/**
 * Registry jobs run from billing paths (payment recording) — they must never
 * throw back into billing (sync queue). Failures mark the domain `failed`;
 * domains:sync and staff can retry. Register/renew SPEND REAL REGISTRY CREDIT:
 * every job guards on the exact pending state so a double-fire is a no-op.
 */
abstract class BaseDomainJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public int $tries = 1; // paid operations: never blind-retry; sync/reconcile handles follow-up

    protected function driver(Domain $domain): RegistrarDriver
    {
        return app(DomainRegistrarManager::class)->driverFor($domain->tenant_id, $domain->id);
    }

    protected function guard(Domain $domain, \Closure $fn): void
    {
        try {
            $fn();
        } catch (\Throwable $e) {
            $domain->update(['status' => 'failed']);
            Log::error(static::class . " failed for domain {$domain->name}", ['error' => $e->getMessage()]);
        }
    }

    /** Pull registry truth into the local row after a successful mutation. */
    protected function syncFromRegistry(Domain $domain): void
    {
        try {
            $info = $this->driver($domain)->info($domain->name);
            $domain->update([
                'registered_at'     => substr((string) ($info['cr_date'] ?? ''), 0, 10) ?: $domain->registered_at,
                'expires_at'        => substr((string) ($info['ex_date'] ?? ''), 0, 10) ?: $domain->expires_at,
                'registrant_handle' => $info['registrant'] ?? $domain->registrant_handle,
                'nsset_handle'      => $info['nsset'] ?? $domain->nsset_handle,
                'keyset_handle'     => $info['keyset'] ?? $domain->keyset_handle,
                'epp_auth_info'     => $info['auth_info'] ?? $domain->epp_auth_info,
            ]);
        } catch (\Throwable $e) {
            Log::warning("Post-action registry sync failed for {$domain->name}: {$e->getMessage()}");
        }
    }

    protected function clearPending(Domain $domain): void
    {
        $meta = $domain->meta ?? [];
        unset($meta['pending_action'], $meta['pending_years']);
        $domain->update(['meta' => $meta]);
    }
}

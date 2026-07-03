<?php

namespace App\Console\Commands;

use App\Models\CronLog;
use App\Models\Domain;
use App\Services\Registrar\DomainRegistrarManager;
use Illuminate\Console\Command;

/**
 * Nightly registry sync: the registry is the source of truth for expiry and
 * existence. Also watches registrar credit and flags low balances.
 */
class SyncDomains extends Command
{
    protected $signature = 'domains:sync {--credit-threshold=50000 : Warn when a zone credit falls below this (TZS)}';
    protected $description = 'Sync domain status/expiry from the registry and check registrar credit';

    public function handle(DomainRegistrarManager $registrar): int
    {
        $startedAt = now();
        $synced = 0;
        $errors = 0;
        $lowCredit = [];

        $domains = Domain::withoutGlobalScopes()
            ->whereIn('status', ['active', 'expired', 'pending'])
            ->get();

        $unmanaged = 0;
        $purged = 0;

        foreach ($domains as $domain) {
            // Never touch orders still awaiting payment.
            if ($domain->status === 'pending' && ($domain->meta['pending_action'] ?? null)) {
                continue;
            }

            // The FRED driver only serves .tz — gTLDs imported from WHMCS are
            // unmanaged until a gTLD registrar driver exists. Flag once, skip after.
            if (!str_ends_with($domain->name, '.tz')) {
                if (!($domain->meta['unmanaged'] ?? false)) {
                    $domain->update(['meta' => array_merge($domain->meta ?? [], ['unmanaged' => true])]);
                }
                $unmanaged++;
                continue;
            }

            try {
                $info = $registrar->driverFor($domain->tenant_id, $domain->id)->info($domain->name);

                $expires = substr((string) ($info['ex_date'] ?? ''), 0, 10) ?: null;
                $status = $domain->status;
                if ($expires) {
                    $status = \Carbon\Carbon::parse($expires)->isPast() ? 'expired' : 'active';
                }

                $domain->update([
                    'status'            => $status,
                    'registered_at'     => substr((string) ($info['cr_date'] ?? ''), 0, 10) ?: $domain->registered_at,
                    'expires_at'        => $expires ?? $domain->expires_at,
                    'registrant_handle' => $info['registrant'] ?? $domain->registrant_handle,
                    'nsset_handle'      => $info['nsset'] ?? $domain->nsset_handle,
                    'keyset_handle'     => $info['keyset'] ?? $domain->keyset_handle,
                    'meta'              => array_merge($domain->meta ?? [], ['last_synced_at' => now()->toIso8601String()], $this->probeSsl($domain->name)),
                ]);
                $synced++;
            } catch (\Throwable $e) {
                // EPP 2303 = object does not exist: the registry purged it
                // (lapsed long ago). Close it out instead of erroring nightly.
                if (str_contains($e->getMessage(), '2303')) {
                    $domain->update([
                        'status' => 'cancelled',
                        'meta'   => array_merge($domain->meta ?? [], [
                            'registry_missing' => true,
                            'closed_by_sync_at' => now()->toIso8601String(),
                        ]),
                    ]);
                    $purged++;
                    $this->line("Purged at registry — closed: {$domain->name}");
                    continue;
                }
                $errors++;
                $this->warn("Sync failed {$domain->name}: {$e->getMessage()}");
            }
        }

        // Registrar credit watch (platform account).
        $threshold = (float) $this->option('credit-threshold');
        try {
            $account = \App\Models\RegistrarAccount::whereNull('tenant_id')->where('is_active', true)->first();
            if ($account) {
                $credits = (new \App\Services\Registrar\FredHttpDriver($account))->credit();
                foreach ($credits as $c) {
                    // Only watch zones that actually hold credit / are in use.
                    if ((float) $c['credit'] > 0 && (float) $c['credit'] < $threshold) {
                        $lowCredit[] = "{$c['zone']}: {$c['credit']}";
                        $this->warn("LOW REGISTRY CREDIT — {$c['zone']}: {$c['credit']} TZS");
                    }
                }
            }
        } catch (\Throwable $e) {
            $this->warn("Credit check failed: {$e->getMessage()}");
        }

        $this->info("Synced {$synced}, unmanaged(gTLD) {$unmanaged}, purged {$purged}, errors {$errors}" . ($lowCredit ? ', LOW CREDIT: ' . implode(' | ', $lowCredit) : ''));

        CronLog::create([
            'tenant_id'   => null,
            'command'     => $this->signature,
            'description' => "Synced {$synced} domains ({$unmanaged} unmanaged gTLDs, {$purged} purged, {$errors} errors)" . ($lowCredit ? ' — LOW CREDIT: ' . implode(' | ', $lowCredit) : ''),
            'results'     => ['synced' => $synced, 'unmanaged' => $unmanaged, 'purged' => $purged, 'errors' => $errors, 'low_credit' => $lowCredit],
            'status'      => $errors > 0 ? 'failed' : 'success',
            'started_at'  => $startedAt,
            'finished_at' => now(),
        ]);

        return self::SUCCESS;
    }

    /**
     * Best-effort TLS certificate check on the domain's website (port 443).
     * Shown to clients in the portal ("Valid SSL, expires ..."). Failures are
     * normal (no site / no SSL) and recorded as ssl_valid=false.
     */
    private function probeSsl(string $domain): array
    {
        try {
            $ctx = stream_context_create(['ssl' => [
                'capture_peer_cert' => true,
                'verify_peer'       => true,
                'verify_peer_name'  => true,
                'SNI_enabled'       => true,
            ]]);
            $sock = @stream_socket_client("ssl://{$domain}:443", $errno, $errstr, 6, STREAM_CLIENT_CONNECT, $ctx);
            if (!$sock) {
                return ['ssl_valid' => false, 'ssl_expires_at' => null];
            }
            $cert = stream_context_get_params($sock)['options']['ssl']['peer_certificate'] ?? null;
            fclose($sock);
            if (!$cert) {
                return ['ssl_valid' => false, 'ssl_expires_at' => null];
            }
            $parsed = openssl_x509_parse($cert);
            $validTo = isset($parsed['validTo_time_t']) ? date('Y-m-d', $parsed['validTo_time_t']) : null;

            return [
                'ssl_valid'      => $validTo !== null && $parsed['validTo_time_t'] > time(),
                'ssl_expires_at' => $validTo,
            ];
        } catch (\Throwable) {
            return ['ssl_valid' => false, 'ssl_expires_at' => null];
        }
    }
}

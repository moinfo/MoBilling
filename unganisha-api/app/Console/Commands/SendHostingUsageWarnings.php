<?php

namespace App\Console\Commands;

use App\Exceptions\WhmApiException;
use App\Models\CronLog;
use App\Models\HostingAccount;
use App\Models\Server;
use App\Models\Tenant;
use App\Notifications\HostingUsageWarningNotification;
use App\Services\WhmService;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Log;

/**
 * Warns clients (email/SMS/WhatsApp/push, per the tenant's own reminder
 * channel toggles — same as domain expiry reminders) when a hosting
 * account's disk or bandwidth usage crosses 85% ("nearing") or 100%
 * ("full"). Disk usage is read from the meta cache hosting:reconcile
 * already refreshes nightly for every account; bandwidth isn't cached
 * anywhere yet, so it's fetched fresh here — one showbw call per server
 * covers every account on it, not one call per account.
 *
 * Deduped via hosting_accounts.meta.usage_warnings_sent.{disk,bandwidth}
 * (the highest mark already sent) so a client isn't re-notified every
 * day while sitting above a threshold; the key clears itself once usage
 * drops back below 85%, so a later re-crossing (or bandwidth's monthly
 * reset) notifies again.
 */
class SendHostingUsageWarnings extends Command
{
    protected $signature = 'hosting:send-usage-warnings {--dry-run}';
    protected $description = "Warn clients when a hosting account's disk or bandwidth usage is nearing or at its limit";

    public const MARKS = [85, 100];

    private bool $dry = false;

    public function handle(): int
    {
        $this->dry = (bool) $this->option('dry-run');
        $startedAt = now();
        $sent = 0;
        $errors = 0;
        $tenantCache = [];

        foreach (Server::withoutGlobalScopes()->where('is_active', true)->get() as $server) {
            $whm = new WhmService($server);

            try {
                $bwByUser = collect($whm->bandwidthUsage())
                    ->keyBy(fn ($r) => strtolower((string) ($r['user'] ?? '')));
            } catch (WhmApiException $e) {
                $errors++;
                $this->warn("Bandwidth fetch failed for {$server->name}: {$e->getMessage()}");
                $bwByUser = collect();
            }

            $accounts = HostingAccount::withoutGlobalScopes()
                ->where('server_id', $server->id)
                ->where('status', 'active')
                ->with(['subscription' => fn ($q) => $q->withoutGlobalScopes()->with(['client' => fn ($q2) => $q2->withoutGlobalScopes()])])
                ->get();

            foreach ($accounts as $account) {
                $client = $account->subscription?->client;
                if (!$client || (!$client->email && !$client->phone)) {
                    continue;
                }

                if (!array_key_exists($account->tenant_id, $tenantCache)) {
                    $tenantCache[$account->tenant_id] = Tenant::withoutGlobalScopes()->find($account->tenant_id);
                }
                $tenant = $tenantCache[$account->tenant_id];
                if (!$tenant) {
                    continue;
                }

                try {
                    $diskPct = $this->diskPercent($account);
                    if ($diskPct !== null) {
                        $sent += $this->checkMetric($account, $client, $tenant, 'disk', $diskPct) ? 1 : 0;
                    }

                    $bwRow = $bwByUser->get(strtolower($account->cpanel_username));
                    $bwPct = $this->bandwidthPercent($bwRow);
                    if ($bwPct !== null) {
                        $sent += $this->checkMetric($account, $client, $tenant, 'bandwidth', $bwPct) ? 1 : 0;
                    }
                } catch (\Throwable $e) {
                    $errors++;
                    Log::warning('SendHostingUsageWarnings failed', ['account' => $account->domain, 'error' => $e->getMessage()]);
                }
            }
        }

        $this->info(($this->dry ? '[dry] ' : '') . "Done. Warnings sent: {$sent}, errors: {$errors}");

        if ($this->dry) {
            return self::SUCCESS;
        }

        CronLog::create([
            'tenant_id' => null,
            'command' => $this->signature,
            'description' => "Sent {$sent} usage warning(s), {$errors} errors",
            'results' => compact('sent', 'errors'),
            'status' => $errors > 0 ? 'failed' : 'success',
            'started_at' => $startedAt,
            'finished_at' => now(),
        ]);

        return self::SUCCESS;
    }

    /** "563M" / "4096M" from the nightly-cached meta -> percent used, or null (unlimited/unknown). */
    private function diskPercent(HostingAccount $account): ?float
    {
        $toMb = function ($raw) {
            if (!is_string($raw) || !preg_match('/^(\d+(?:\.\d+)?)M$/i', trim($raw), $m)) {
                return null;
            }
            return (float) $m[1];
        };

        $usedMb = $toMb($account->meta['disk_used'] ?? null);
        $limitMb = $toMb($account->meta['disk_limit'] ?? null);

        if ($usedMb === null || $limitMb === null || $limitMb <= 0) {
            return null;
        }

        return ($usedMb / $limitMb) * 100;
    }

    /** showbw's per-account row -> percent used, or null (unlimited/no row). */
    private function bandwidthPercent(?array $row): ?float
    {
        if (!$row) {
            return null;
        }

        $limitBytes = (int) ($row['limit'] ?? 0);
        if ($limitBytes <= 0) {
            return null;
        }

        $usedBytes = (int) ($row['totalbytes'] ?? 0);

        return ($usedBytes / $limitBytes) * 100;
    }

    /** @param 'disk'|'bandwidth' $metric */
    private function checkMetric(HostingAccount $account, $client, Tenant $tenant, string $metric, float $percent): bool
    {
        $mark = collect(self::MARKS)->filter(fn ($m) => $percent >= $m)->last();

        if ($mark === null) {
            if (!$this->dry && data_get($account->meta, "usage_warnings_sent.{$metric}") !== null) {
                $meta = $account->meta ?? [];
                unset($meta['usage_warnings_sent'][$metric]);
                $account->update(['meta' => $meta]);
            }
            return false;
        }

        $lastSent = data_get($account->meta, "usage_warnings_sent.{$metric}");
        if ($lastSent !== null && $lastSent >= $mark) {
            return false;
        }

        if ($this->dry) {
            $this->line(sprintf('[dry] Would warn: %s — %s at %.0f%% (mark %d) -> %s', $account->domain, $metric, $percent, $mark, $client->name));
            return true;
        }

        $client->notify(new HostingUsageWarningNotification($account, $tenant, $metric, $percent, atLimit: $mark >= 100));

        $meta = $account->meta ?? [];
        $meta['usage_warnings_sent'][$metric] = $mark;
        $account->update(['meta' => $meta]);

        $this->info(sprintf('Warned: %s — %s at %.0f%% (mark %d)', $account->domain, $metric, $percent, $mark));

        return true;
    }
}

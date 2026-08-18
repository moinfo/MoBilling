<?php

namespace App\Console\Commands;

use App\Models\CronLog;
use App\Models\Tenant;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Http;

/**
 * The practical enforcement mechanism for self-hosted installs now that
 * source-code encoding (ionCube etc.) is off the table for cost reasons —
 * re-validates every self-hosted tenant's license against the hosted
 * license server daily and can flip is_active off if it's genuinely gone
 * bad. This is stronger than static code protection in one respect: it's
 * enforced by a server the customer doesn't control, so bypassing it means
 * actually finding and patching every call site, not just copying files.
 *
 * A no-op on mobilling.co.tz itself — there are no is_self_hosted tenants
 * here, so the query below simply matches nothing.
 */
class CheckLicenses extends Command
{
    protected $signature = 'license:check';

    protected $description = 'Re-validate every self-hosted tenant\'s license against the hosted license server';

    /** Days tolerated with no successful check (e.g. the license server or this server's internet is down) before locking the tenant out. Deliberately generous — a false lockout is far worse than a delayed one. */
    private const GRACE_PERIOD_DAYS = 10;

    public function handle(): int
    {
        $startedAt = now();
        $tenants = Tenant::withoutGlobalScopes()
            ->where('is_self_hosted', true)
            ->whereNotNull('license_key')
            ->get();

        $results = ['checked' => 0, 'valid' => 0, 'deactivated' => 0, 'reactivated' => 0, 'network_errors' => 0];

        foreach ($tenants as $tenant) {
            $results['checked']++;
            $outcome = $this->checkOne($tenant);
            $results[$outcome]++;
        }

        $this->info("Checked {$results['checked']} self-hosted tenant(s): {$results['valid']} valid, {$results['deactivated']} deactivated, {$results['reactivated']} reactivated, {$results['network_errors']} unreachable.");

        CronLog::create([
            'tenant_id' => null,
            'command' => $this->signature,
            'description' => "License check: {$results['checked']} tenant(s)",
            'results' => $results,
            'status' => 'success',
            'started_at' => $startedAt,
            'finished_at' => now(),
        ]);

        return self::SUCCESS;
    }

    /** @return string one of: valid, deactivated, reactivated, network_errors */
    private function checkOne(Tenant $tenant): string
    {
        try {
            $response = Http::timeout(10)->post('https://mobilling.co.tz/api/license/validate', [
                'license_key' => $tenant->license_key,
                'domain' => parse_url(config('app.url'), PHP_URL_HOST) ?: config('app.url'),
                'app_version' => config('app.version', 'unknown'),
            ]);
        } catch (\Throwable $e) {
            return $this->handleUnreachable($tenant, $e->getMessage());
        }

        $body = $response->json() ?? [];

        // The server was reached and gave an authoritative answer — trust it immediately either way.
        if ($response->successful() && ($body['valid'] ?? false)) {
            $tenant->update([
                'license_last_valid_at' => now(),
                'license_expires_at' => $body['expires_at'] ?? null,
                'is_active' => true,
            ]);
            return $tenant->wasChanged('is_active') ? 'reactivated' : 'valid';
        }

        if (in_array($response->status(), [403, 422, 404], true)) {
            // Explicit rejection (suspended/expired/invalid key/domain mismatch) — lock out now, no grace period.
            if ($tenant->is_active) {
                $this->warn("Tenant {$tenant->id} deactivated: " . ($body['message'] ?? 'license invalid'));
            }
            $tenant->update(['is_active' => false]);
            return 'deactivated';
        }

        // Anything else (5xx, malformed response) — treat like unreachable, not a rejection.
        return $this->handleUnreachable($tenant, $body['message'] ?? "unexpected status {$response->status()}");
    }

    private function handleUnreachable(Tenant $tenant, string $reason): string
    {
        $lastValid = $tenant->license_last_valid_at;
        $withinGrace = $lastValid && $lastValid->gt(now()->subDays(self::GRACE_PERIOD_DAYS));

        if (!$withinGrace && $tenant->is_active) {
            $tenant->update(['is_active' => false]);
            $this->warn("Tenant {$tenant->id} deactivated: no successful license check in " . self::GRACE_PERIOD_DAYS . "+ days ({$reason})");
            return 'deactivated';
        }

        $this->line("Tenant {$tenant->id}: license server unreachable ({$reason}), within grace period — no action.");
        return 'network_errors';
    }
}

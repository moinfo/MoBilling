<?php

namespace App\Console\Commands;

use App\Models\ClientSubscription;
use App\Models\CronLog;
use App\Models\HostingAccount;
use App\Models\ProductService;
use App\Models\Server;
use App\Services\WhmService;
use Carbon\Carbon;
use Illuminate\Console\Command;

/**
 * Clients who pay for a "Backup" product used to only get a fresh cPanel
 * backup when staff remembered to trigger one by hand. This makes that
 * automatic: for every active subscription to a product in the "Backup"
 * category, resolve the hosting account (the subscription's `label` is the
 * domain name — these backup add-ons aren't linked via
 * hosting_accounts.client_subscription_id, which points at the hosting
 * *plan* subscription instead) and, if its most recent on-server backup is
 * older than the freshness window, trigger a new one now
 * (WhmService::triggerFullBackup — Backup::fullbackup_to_homedir).
 *
 * There is no WHM API1 function this app's reseller token can use to
 * flip an account's own "included in the server's nightly backup"
 * setting (backup_config_get/set and modifyacct both come back
 * "Permission denied" — verified live), so this on-demand trigger is the
 * only lever available, and it's driven by staleness rather than a fixed
 * day so a missed run just catches up next time.
 */
class GeneratePaidBackups extends Command
{
    protected $signature = 'hosting:backup-paid-accounts';
    protected $description = 'Trigger a fresh cPanel backup for hosting accounts whose client has an active "Backup" subscription and no recent backup';

    /** Days a backup is still considered fresh — matches the weekly cadence WHM's own backups already run at. */
    private const FRESHNESS_DAYS = 8;

    public function handle(): int
    {
        $startedAt = now();
        $triggered = 0;
        $skippedFresh = 0;
        $skippedNoAccount = 0;
        $errors = 0;

        $productIds = ProductService::withoutGlobalScopes()
            ->where('category', 'Backup')
            ->pluck('id');

        if ($productIds->isEmpty()) {
            $this->info('No "Backup" category products found.');
            $this->logResult($startedAt, 0, 0, 0, 0, 'success');
            return self::SUCCESS;
        }

        $subscriptions = ClientSubscription::withoutGlobalScopes()
            ->whereIn('product_service_id', $productIds)
            ->active()
            ->get();

        $serverCache = [];

        foreach ($subscriptions as $subscription) {
            $account = HostingAccount::withoutGlobalScopes()
                ->where('tenant_id', $subscription->tenant_id)
                ->where('domain', $subscription->label)
                ->first();

            if (!$account || $account->status !== 'active' || !$account->cpanel_username) {
                $skippedNoAccount++;
                continue;
            }

            try {
                if (!array_key_exists($account->server_id, $serverCache)) {
                    $server = Server::withoutGlobalScopes()->find($account->server_id);
                    $serverCache[$account->server_id] = $server ? new WhmService($server) : null;
                }
                $whm = $serverCache[$account->server_id];

                if (!$whm) {
                    $skippedNoAccount++;
                    continue;
                }

                $dates = $whm->backupDates($account->cpanel_username);
                $latest = collect($dates)->map(fn ($d) => Carbon::parse($d))->sortDesc()->first();

                if ($latest && $latest->greaterThan(now()->subDays(self::FRESHNESS_DAYS))) {
                    $skippedFresh++;
                    continue;
                }

                $whm->triggerFullBackup($account->cpanel_username);
                $triggered++;
                $this->info("Triggered backup: {$account->domain}" . ($latest ? " (last: {$latest->toDateString()})" : ' (no prior backup)'));
            } catch (\Throwable $e) {
                $errors++;
                $this->warn("Failed {$account->domain}: {$e->getMessage()}");
            }
        }

        $this->info("Done. Triggered: {$triggered}, already fresh: {$skippedFresh}, no account: {$skippedNoAccount}, errors: {$errors}");
        $this->logResult($startedAt, $triggered, $skippedFresh, $skippedNoAccount, $errors, $errors > 0 ? 'failed' : 'success');

        return self::SUCCESS;
    }

    private function logResult($startedAt, int $triggered, int $skippedFresh, int $skippedNoAccount, int $errors, string $status): void
    {
        CronLog::create([
            'tenant_id' => null,
            'command' => $this->signature,
            'description' => "Triggered {$triggered} backups, {$skippedFresh} already fresh, {$skippedNoAccount} without a matching account, {$errors} errors",
            'results' => compact('triggered', 'skippedFresh', 'skippedNoAccount', 'errors'),
            'status' => $status,
            'started_at' => $startedAt,
            'finished_at' => now(),
        ]);
    }
}

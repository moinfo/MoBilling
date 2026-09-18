<?php

namespace App\Console\Commands;

use App\Models\ClientSubscription;
use App\Models\CronLog;
use App\Models\Domain;
use App\Models\HostingAccount;
use App\Models\HostingAccountBackupSetting;
use App\Models\ProductService;
use App\Models\Server;
use App\Services\WhmService;
use Carbon\Carbon;
use Illuminate\Console\Command;

/**
 * Clients who pay for a "Backup" product used to only get a fresh cPanel
 * backup when staff remembered to trigger one by hand. This makes that
 * automatic and storage-aware: for every active subscription to a product
 * in the "Backup" category, resolve the hosting account (the
 * subscription's `label` is the domain name — these backup add-ons aren't
 * linked via hosting_accounts.client_subscription_id, which points at the
 * hosting *plan* subscription instead), trigger a backup if today doesn't
 * already have one, then prune old backup files down to a
 * daily/weekly/monthly retention policy (default: keep the last 7 days,
 * plus one weekly and one monthly snapshot) — otherwise a daily full
 * backup would just fill up the client's own disk quota.
 *
 * There is no WHM API1 function this app's reseller token can use to
 * flip an account's own "included in the server's nightly backup"
 * setting, nor a cPanel UAPI Backup-module function to manage retention
 * (backup_config_get/set and modifyacct come back "Permission denied";
 * Backup::delete_backup and every other delete-shaped name tried simply
 * doesn't exist — all verified live). So both halves of this are done
 * with generic primitives instead: Backup::fullbackup_to_homedir to
 * generate, and Fileman::list_files / Fileman::delete_file — confirmed
 * real live — to prune the resulting tarballs directly.
 */
class GeneratePaidBackups extends Command
{
    protected $signature = 'hosting:backup-paid-accounts';
    protected $description = 'Trigger a daily cPanel backup for hosting accounts on an active "Backup" subscription, and prune old ones to each account\'s retention policy';

    public function handle(): int
    {
        $startedAt = now();
        $triggered = 0;
        $alreadyToday = 0;
        $pruned = 0;
        $skippedNoAccount = 0;
        $skippedExpiredDomain = 0;
        $skippedLowDisk = 0;
        $errors = 0;

        $productIds = ProductService::withoutGlobalScopes()
            ->where('category', 'Backup')
            ->pluck('id');

        if ($productIds->isEmpty()) {
            $this->info('No "Backup" category products found.');
            $this->logResult($startedAt, 0, 0, 0, 0, 0, 0, 0, 'success');
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

            $domain = Domain::withoutGlobalScopes()
                ->where('tenant_id', $subscription->tenant_id)
                ->where('name', $subscription->label)
                ->first();

            $domainExpired = $domain && ($domain->status !== 'active' || ($domain->expires_at && $domain->expires_at->isPast()));

            if ($domainExpired) {
                $skippedExpiredDomain++;
                $this->line("Skipped (domain not active/expired): {$account->domain}");
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

                $files = $whm->homeDirBackupFiles($account->cpanel_username);
                $hasToday = collect($files)->contains(fn ($f) => Carbon::createFromTimestamp($f['mtime'])->isToday());

                if ($hasToday) {
                    $alreadyToday++;
                } elseif (!$this->hasHeadroom($whm, $account->cpanel_username)) {
                    $skippedLowDisk++;
                    $this->warn("Skipped (not enough free disk quota for a backup): {$account->domain}");
                } else {
                    $whm->triggerFullBackup($account->cpanel_username);
                    $triggered++;
                    $this->info("Triggered backup: {$account->domain}");
                    // Re-list so the just-created file is included in pruning below
                    // (it's timestamped today, so it always survives the cut anyway,
                    // but this keeps the log/prune count honest for this run).
                    $files = $whm->homeDirBackupFiles($account->cpanel_username);
                }

                $settings = HostingAccountBackupSetting::withoutGlobalScopes()
                    ->where('hosting_account_id', $account->id)
                    ->first();

                $toDelete = $this->pruneList(
                    $files,
                    $settings->daily_retention_days ?? HostingAccountBackupSetting::DEFAULT_DAILY_RETENTION_DAYS,
                    $settings->keep_weekly ?? true,
                    $settings->keep_monthly ?? true,
                );

                foreach ($toDelete as $file) {
                    $whm->deleteFile($account->cpanel_username, $file['path']);
                    $pruned++;
                }
                if ($toDelete) {
                    $this->line("Pruned " . count($toDelete) . " old backup(s): {$account->domain}");
                }
            } catch (\Throwable $e) {
                $errors++;
                $this->warn("Failed {$account->domain}: {$e->getMessage()}");
            }
        }

        $this->info("Done. Triggered: {$triggered}, already had today's: {$alreadyToday}, pruned: {$pruned}, no account: {$skippedNoAccount}, expired domain: {$skippedExpiredDomain}, low disk: {$skippedLowDisk}, errors: {$errors}");
        $this->logResult($startedAt, $triggered, $alreadyToday, $pruned, $skippedNoAccount, $skippedExpiredDomain, $skippedLowDisk, $errors, $errors > 0 ? 'failed' : 'success');

        return self::SUCCESS;
    }

    /**
     * A full backup lands in the account's own home directory and counts
     * against its disk quota — triggering one for an account that's already
     * nearly full would risk pushing it over quota (which can block new
     * mail/uploads). Requires at least as much free space as the account
     * is currently using, a conservative stand-in for "the backup, even
     * poorly compressed, should still fit." Unlimited-quota accounts
     * always pass.
     */
    private function hasHeadroom(WhmService $whm, string $user): bool
    {
        $summary = $whm->accountSummary($user);
        $toMb = function ($raw) {
            if (!is_string($raw) || !preg_match('/^(\d+(?:\.\d+)?)M$/i', trim($raw), $m)) {
                return null;
            }
            return (float) $m[1];
        };

        $usedMb = $toMb($summary['diskused'] ?? null) ?? 0;
        $limitMb = $toMb($summary['disklimit'] ?? null);

        if ($limitMb === null) {
            return true;
        }

        return ($limitMb - $usedMb) >= $usedMb;
    }

    /**
     * Every file within the last $dailyDays is kept unconditionally. Beyond
     * that, $keepWeekly keeps exactly one further checkpoint — the newest
     * file that's at least $dailyDays+7 days old — and $keepMonthly keeps
     * exactly one more beyond that — the newest file at least $dailyDays+30
     * days old. Anything in between (too old for the daily window, not old
     * enough to be a real week/month-old checkpoint) is deleted, along
     * with everything past the single monthly checkpoint. Returns the
     * files that should be DELETED. Recomputed fresh from the current file
     * list every run, so it's idempotent regardless of which day it runs.
     */
    private function pruneList(array $files, int $dailyDays, bool $keepWeekly, bool $keepMonthly): array
    {
        $dailyCutoff = Carbon::now()->subDays($dailyDays)->startOfDay();
        $weeklyCutoff = Carbon::now()->subDays($dailyDays + 7)->startOfDay();
        $monthlyCutoff = Carbon::now()->subDays($dailyDays + 30)->startOfDay();

        $keepPaths = collect($files)
            ->filter(fn ($f) => Carbon::createFromTimestamp($f['mtime'])->greaterThanOrEqualTo($dailyCutoff))
            ->pluck('path')
            ->all();

        if ($keepWeekly) {
            $weeklyKeeper = collect($files)
                ->filter(fn ($f) => Carbon::createFromTimestamp($f['mtime'])->lessThanOrEqualTo($weeklyCutoff))
                ->sortByDesc('mtime')
                ->first();
            if ($weeklyKeeper) {
                $keepPaths[] = $weeklyKeeper['path'];
            }
        }

        if ($keepMonthly) {
            $monthlyKeeper = collect($files)
                ->filter(fn ($f) => Carbon::createFromTimestamp($f['mtime'])->lessThanOrEqualTo($monthlyCutoff))
                ->sortByDesc('mtime')
                ->first();
            if ($monthlyKeeper) {
                $keepPaths[] = $monthlyKeeper['path'];
            }
        }

        $keepPaths = array_unique($keepPaths);

        return array_values(array_filter($files, fn ($f) => !in_array($f['path'], $keepPaths, true)));
    }

    private function logResult($startedAt, int $triggered, int $alreadyToday, int $pruned, int $skippedNoAccount, int $skippedExpiredDomain, int $skippedLowDisk, int $errors, string $status): void
    {
        CronLog::create([
            'tenant_id' => null,
            'command' => $this->signature,
            'description' => "Triggered {$triggered} backups, {$alreadyToday} already had today's, pruned {$pruned} old files, {$skippedNoAccount} without a matching account, {$skippedExpiredDomain} with an expired domain, {$skippedLowDisk} skipped for low disk, {$errors} errors",
            'results' => compact('triggered', 'alreadyToday', 'pruned', 'skippedNoAccount', 'skippedExpiredDomain', 'skippedLowDisk', 'errors'),
            'status' => $status,
            'started_at' => $startedAt,
            'finished_at' => now(),
        ]);
    }
}

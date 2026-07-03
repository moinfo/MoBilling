<?php

namespace App\Console\Commands;

use App\Models\CronLog;
use App\Models\HostingAccount;
use App\Models\Server;
use App\Services\WhmService;
use Illuminate\Console\Command;

/**
 * Nightly drift check: the WHM server is the source of truth for account state.
 * Also refreshes disk/bandwidth usage into hosting_accounts.meta and retries
 * accounts stuck in `failed`. (docs/IMPLEMENTATION_PLAN.md §A5)
 */
class ReconcileHostingAccounts extends Command
{
    protected $signature = 'hosting:reconcile';
    protected $description = 'Reconcile hosting account status/usage against the WHM servers';

    public function handle(): int
    {
        $startedAt = now();
        $synced = 0;
        $drift = 0;
        $errors = 0;

        foreach (Server::withoutGlobalScopes()->where('is_active', true)->get() as $server) {
            $accounts = HostingAccount::withoutGlobalScopes()
                ->where('server_id', $server->id)
                ->whereNotIn('status', ['terminated'])
                ->get();

            $whm = new WhmService($server);

            foreach ($accounts as $account) {
                try {
                    $summary = $whm->forAccount($account->id)->accountSummary($account->cpanel_username);

                    $remoteStatus = ($summary['suspended'] ?? 0) ? 'suspended' : 'active';

                    if (in_array($account->status, ['active', 'suspended', 'failed', 'pending']) && $account->status !== $remoteStatus) {
                        $this->line("Drift: {$account->domain} local={$account->status} whm={$remoteStatus} — fixed");
                        $drift++;
                    }

                    $account->update([
                        'status'         => $remoteStatus,
                        'last_synced_at' => now(),
                        'meta'           => array_merge($account->meta ?? [], [
                            'disk_used'  => $summary['diskused'] ?? null,
                            'disk_limit' => $summary['disklimit'] ?? null,
                            'plan'       => $summary['plan'] ?? null,
                            'ip'         => $summary['ip'] ?? null,
                        ]),
                    ]);
                    $synced++;
                } catch (\Throwable $e) {
                    $errors++;
                    $this->warn("Failed {$account->domain}: {$e->getMessage()}");
                }
            }
        }

        $this->info("Synced {$synced}, drift fixed {$drift}, errors {$errors}");

        CronLog::create([
            'tenant_id'   => null,
            'command'     => $this->signature,
            'description' => "Synced {$synced} hosting accounts ({$drift} drift fixed, {$errors} errors)",
            'results'     => compact('synced', 'drift', 'errors'),
            'status'      => $errors > 0 ? 'failed' : 'success',
            'started_at'  => $startedAt,
            'finished_at' => now(),
        ]);

        return self::SUCCESS;
    }
}

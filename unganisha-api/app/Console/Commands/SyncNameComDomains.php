<?php

namespace App\Console\Commands;

use App\Models\CronLog;
use App\Models\NameComAccount;
use App\Services\Registrar\NameComBulkSync;
use Illuminate\Console\Command;

/** Nightly read-only refresh of every Name.com-linked domain (expiry, status, nameservers, lock, autorenew, privacy). */
class SyncNameComDomains extends Command
{
    protected $signature = 'namecom:sync-domains';
    protected $description = 'Refresh all Name.com-linked domains from Name.com (read-only, paced)';

    public function handle(NameComBulkSync $bulk): int
    {
        $started = now();
        $tenantIds = NameComAccount::withoutGlobalScopes()->distinct()->pluck('tenant_id');
        $tot = ['processed' => 0, 'updated' => 0, 'unchanged' => 0, 'failed' => 0, 'skipped' => 0];
        try {
            foreach ($tenantIds as $tid) {
                $r = $bulk->runAll($tid);
                foreach ($tot as $k => $_) $tot[$k] += $r[$k];
            }
        } catch (\Throwable $e) {
            CronLog::create(['tenant_id' => null, 'command' => $this->signature, 'description' => 'Name.com refresh crashed', 'results' => $tot,
                'status' => 'failed', 'error' => mb_substr($e->getMessage(), 0, 500), 'started_at' => $started, 'finished_at' => now()]);
            return self::FAILURE;
        }
        $desc = "Name.com refresh: {$tot['processed']} checked, {$tot['updated']} changed, {$tot['unchanged']} unchanged, {$tot['failed']} failed, {$tot['skipped']} skipped";
        $this->info($desc);
        CronLog::create(['tenant_id' => null, 'command' => $this->signature, 'description' => $desc, 'results' => $tot,
            'status' => 'success', 'started_at' => $started, 'finished_at' => now()]);
        return self::SUCCESS;
    }
}

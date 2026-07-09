<?php

namespace App\Console\Commands;

use App\Models\Permission;
use App\Models\Tenant;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Reconcile every tenant's permission allowlist (tenant_permissions) so newly
 * added permissions become assignable. RegisterController grants all
 * permissions to NEW tenants; this does the same catch-up for EXISTING ones.
 *
 * Run after adding new permissions (until each permission migration reliably
 * backfills tenants itself). Idempotent — only inserts what's missing, never
 * removes, so it won't undo a super-admin's intentional per-tenant restriction
 * of an already-known permission.
 */
class SyncTenantPermissions extends Command
{
    protected $signature = 'permissions:sync-tenants {--dry-run : Report gaps without changing anything}';
    protected $description = 'Grant any permissions missing from each tenant allowlist (closes propagation gaps)';

    public function handle(): int
    {
        $allPermIds = Permission::pluck('id');
        $dry = (bool) $this->option('dry-run');
        $totalAdded = 0;

        foreach (Tenant::all() as $tenant) {
            $have = DB::table('tenant_permissions')->where('tenant_id', $tenant->id)->pluck('permission_id');
            $missing = $allPermIds->diff($have);
            if ($missing->isEmpty()) {
                continue;
            }

            $this->line(sprintf('%-40s %d missing', $tenant->name, $missing->count()));
            $totalAdded += $missing->count();

            if (!$dry) {
                $rows = $missing->map(fn ($pid) => ['tenant_id' => $tenant->id, 'permission_id' => $pid])->all();
                foreach (array_chunk($rows, 500) as $chunk) {
                    DB::table('tenant_permissions')->insertOrIgnore($chunk);
                }
            }
        }

        $this->info($dry
            ? "Dry run: {$totalAdded} tenant-permission grants would be added."
            : "Done: {$totalAdded} tenant-permission grants added.");

        return self::SUCCESS;
    }
}

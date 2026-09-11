<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Reconciliation, not a new feature: several past permission-seeding
 * migrations (e.g. 2026_08_14_090400_seed_employees_permissions.php)
 * granted a new permission to `permissions` + `role_permissions` but
 * forgot the `tenant_permissions` loop — see [[three-layer-permission-system]].
 * That silently blocked RoleController::store()/update() ("Some
 * permissions are not available for your organization") for any tenant
 * that existed when the migration ran, since a role can only be given a
 * permission its tenant itself has. Audited live and found 6 affected
 * tenants (7 to 63 permissions missing each). Fixes it the same way every
 * correct seeding migration already does: grant every tenant every
 * permission it doesn't yet have in tenant_permissions.
 */
return new class extends Migration
{
    public function up(): void
    {
        $permIds = DB::table('permissions')->pluck('id');
        $tenantIds = DB::table('tenants')->pluck('id');

        $rows = [];
        foreach ($tenantIds as $tenantId) {
            foreach ($permIds as $permId) {
                $rows[] = ['tenant_id' => $tenantId, 'permission_id' => $permId];
                if (count($rows) >= 1000) {
                    DB::table('tenant_permissions')->insertOrIgnore($rows);
                    $rows = [];
                }
            }
        }
        if ($rows) {
            DB::table('tenant_permissions')->insertOrIgnore($rows);
        }
    }

    public function down(): void
    {
        // Not reversible — no record of which grants pre-existed vs were backfilled.
    }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Defensive re-assertion that the System Records Report permissions are
 * assigned to every existing role + tenant. Mirrors 2026_06_09_100009
 * (which did the same for the dashboard widget permissions).
 *
 * Idempotent — insertOrIgnore against the (role_id, permission_id) and
 * (tenant_id, permission_id) unique keys, so re-running is a no-op.
 *
 * Why bother if 2026_06_09_100010 already did this? Two reasons:
 *  1. Discoverability — operators searching "who has the system records
 *     report?" land on a clearly-named file.
 *  2. Safety net — fills any gap (e.g. a tenant or role created mid-seed).
 *
 * Fails loud if the underlying permissions don't exist (run 100010 first).
 */
return new class extends Migration
{
    public function up(): void
    {
        $permIds = DB::table('permissions')
            ->whereIn('name', [
                'menu.report_system_records',
                'reports.system_records',
            ])
            ->pluck('id');

        if ($permIds->isEmpty()) {
            throw new \RuntimeException(
                'System Records Report permissions not found. Run 2026_06_09_100010_seed_system_records_report_permission first.'
            );
        }

        $roleGrants = 0;
        $tenantGrants = 0;

        foreach (DB::table('roles')->pluck('id') as $roleId) {
            foreach ($permIds as $permId) {
                $roleGrants += DB::table('role_permissions')->insertOrIgnore([
                    'role_id'       => $roleId,
                    'permission_id' => $permId,
                ]);
            }
        }

        foreach (DB::table('tenants')->pluck('id') as $tenantId) {
            foreach ($permIds as $permId) {
                $tenantGrants += DB::table('tenant_permissions')->insertOrIgnore([
                    'tenant_id'     => $tenantId,
                    'permission_id' => $permId,
                ]);
            }
        }

        DB::statement("SELECT '$roleGrants role_permissions + $tenantGrants tenant_permissions newly inserted' AS info");
    }

    public function down(): void
    {
        // Revoking would also undo the prior seeder. Intentionally no-op.
        // To remove from a role, use the Roles UI.
    }
};

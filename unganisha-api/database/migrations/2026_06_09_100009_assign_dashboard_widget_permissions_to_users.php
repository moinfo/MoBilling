<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Defensive re-assertion that the two new dashboard widget permissions
 * are assigned to every existing role (in every tenant) and every tenant's
 * allowlist. Idempotent — uses insertOrIgnore against the unique keys,
 * so running this on a DB where the prior seeder already granted them
 * is a no-op.
 *
 * Why bother if 2026_06_09_100008 already did this? Two reasons:
 *   1. Explicit migration history — a future reader looking at "who has
 *      the new dashboard widgets" can find the answer in one named file.
 *   2. Safety net for any environment where the seeder might have skipped
 *      a row (e.g. a tenant created in a transaction that hadn't committed
 *      when the seeder ran, or a manual ALTER that dropped a row).
 */
return new class extends Migration
{
    public function up(): void
    {
        $permIds = DB::table('permissions')
            ->whereIn('name', [
                'dashboard.system_records_breakdown',
                'dashboard.bank_account_breakdown',
            ])
            ->pluck('id');

        if ($permIds->isEmpty()) {
            // The 100008 seeder hasn't run for some reason — bail loudly so
            // operators notice rather than silently leaving an empty assignment.
            throw new \RuntimeException(
                'Dashboard widget permissions not found. Run 2026_06_09_100008_seed_dashboard_system_records_permissions first.'
            );
        }

        $roleGrants = 0;
        $tenantGrants = 0;

        foreach (DB::table('roles')->pluck('id') as $roleId) {
            foreach ($permIds as $permId) {
                $inserted = DB::table('role_permissions')->insertOrIgnore([
                    'role_id'       => $roleId,
                    'permission_id' => $permId,
                ]);
                $roleGrants += $inserted;
            }
        }

        foreach (DB::table('tenants')->pluck('id') as $tenantId) {
            foreach ($permIds as $permId) {
                $inserted = DB::table('tenant_permissions')->insertOrIgnore([
                    'tenant_id'     => $tenantId,
                    'permission_id' => $permId,
                ]);
                $tenantGrants += $inserted;
            }
        }

        // Visible in `php artisan migrate` output via the console driver.
        DB::statement("SELECT '$roleGrants role_permissions + $tenantGrants tenant_permissions newly inserted' AS info");
    }

    public function down(): void
    {
        // Revoking the grants would undo the prior seeder too. Intentionally
        // no-op — to remove dashboard widgets from a role, use the Roles UI.
    }
};

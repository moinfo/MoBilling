<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Defensive re-assertion that the System Verifications + reports permissions
 * are assigned to the right scope. Idempotent (insertOrIgnore against the
 * unique keys), so re-running is a no-op.
 *
 * Coverage matrix:
 *   admin role only       → menu.system_verifications, system_verifications.*
 *                          system_verification_reports.read,
 *                          menu.report_system_verifications,
 *                          reports.system_verifications
 *
 *   every role            → menu.my_verifications,
 *                          system_verification_reports.submit
 *
 * Tenants get every permission enabled.
 *
 * Fails loud if the underlying permissions don't exist (run 100002 + 100004
 * first).
 */
return new class extends Migration
{
    public function up(): void
    {
        $adminOnlyNames = [
            'menu.system_verifications',
            'system_verifications.read', 'system_verifications.create',
            'system_verifications.update', 'system_verifications.delete',
            'system_verification_reports.read',
            'menu.report_system_verifications',
            'reports.system_verifications',
        ];

        $everyRoleNames = [
            'menu.my_verifications',
            'system_verification_reports.submit',
        ];

        $allNames = array_merge($adminOnlyNames, $everyRoleNames);
        $allPermIds = DB::table('permissions')->whereIn('name', $allNames)->pluck('id', 'name');

        $missing = array_diff($allNames, array_keys($allPermIds->all()));
        if (!empty($missing)) {
            throw new \RuntimeException(
                'Missing permissions: ' . implode(', ', $missing)
                . ' — run 100002 + 100004 first.'
            );
        }

        $adminPermIds = collect($adminOnlyNames)->map(fn ($n) => $allPermIds[$n]);
        $everyRolePermIds = collect($everyRoleNames)->map(fn ($n) => $allPermIds[$n]);

        $roleGrants = 0;
        $tenantGrants = 0;

        // Admin-only permissions → grant only to roles named 'admin'
        foreach (DB::table('roles')->where('name', 'admin')->pluck('id') as $roleId) {
            foreach ($adminPermIds as $permId) {
                $roleGrants += DB::table('role_permissions')->insertOrIgnore([
                    'role_id'       => $roleId,
                    'permission_id' => $permId,
                ]);
            }
        }

        // Staff-facing permissions → grant to every role
        foreach (DB::table('roles')->pluck('id') as $roleId) {
            foreach ($everyRolePermIds as $permId) {
                $roleGrants += DB::table('role_permissions')->insertOrIgnore([
                    'role_id'       => $roleId,
                    'permission_id' => $permId,
                ]);
            }
        }

        // Every permission gets enabled on every tenant's allowlist.
        foreach (DB::table('tenants')->pluck('id') as $tenantId) {
            foreach ($allPermIds as $permId) {
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
        // No-op. To revoke per-role permissions, use the Roles management UI.
    }
};

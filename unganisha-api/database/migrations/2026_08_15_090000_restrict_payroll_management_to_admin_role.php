<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * payroll.manage/payroll.view were blanket-granted to every role when
 * seeded (2026_08_14_091200_seed_payroll_permissions) — salary/statutory
 * data is sensitive enough that only a tenant's Administrator role should
 * see the HR-admin payroll surface by default; other roles can still be
 * granted it explicitly via the Roles UI. menu.payroll is deliberately
 * left alone (still granted broadly) — it only gates nav visibility, and
 * revoking it would also hide the "My Payslips" self-service tab from
 * every non-admin employee, which is the opposite of the intent here
 * (Payroll.tsx renders that tab unconditionally regardless of
 * payroll.manage/.view, so a non-admin sees only their own payslips
 * once these two are revoked).
 *
 * Also registers all three payroll permissions into every tenant's
 * tenant_permissions allowlist (see SyncTenantPermissions) since the
 * original seed never did — without it, a tenant admin couldn't assign
 * payroll.manage/.view to a custom role from the Roles UI even after
 * explicitly wanting to.
 */
return new class extends Migration
{
    public function up(): void
    {
        $allPermIds = DB::table('permissions')
            ->where(fn ($q) => $q->where('name', 'like', 'payroll.%')->orWhere('name', 'menu.payroll'))
            ->pluck('id');

        if ($allPermIds->isEmpty()) {
            return;
        }

        $restrictedPermIds = DB::table('permissions')
            ->whereIn('name', ['payroll.manage', 'payroll.view'])
            ->pluck('id');

        $nonAdminRoleIds = DB::table('roles')->where('name', '!=', 'admin')->pluck('id');

        DB::table('role_permissions')
            ->whereIn('permission_id', $restrictedPermIds)
            ->whereIn('role_id', $nonAdminRoleIds)
            ->delete();

        $tenantIds = DB::table('tenants')->pluck('id');
        foreach ($tenantIds as $tenantId) {
            $rows = $allPermIds->map(fn ($permId) => ['tenant_id' => $tenantId, 'permission_id' => $permId])->all();
            foreach (array_chunk($rows, 500) as $chunk) {
                DB::table('tenant_permissions')->insertOrIgnore($chunk);
            }
        }
    }

    public function down(): void
    {
        // Data-only, one-directional restriction — re-granting to every
        // role would just recreate the over-broad state this fixes.
    }
};

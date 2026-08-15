<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * leave.view_all/leave.review/leave.manage were blanket-granted to every
 * role when seeded (Phase 1) — same over-broad default the payroll
 * permissions had (see 2026_08_15_090000_restrict_payroll_management_to_admin_role).
 * Staff should only see their own leave requests/balance by default;
 * seeing everyone else's requests and approving/rejecting them is an
 * admin action. menu.leave and leave.submit are deliberately left broadly
 * granted — Leave.tsx renders "Dashboard" (own balance) and "My Requests"
 * (own requests, self-service submit) unconditionally regardless of these
 * three permissions, so revoking menu.leave would have hidden that
 * self-service surface too, and leave.submit is never actually checked in
 * LeaveRequestController::store() (self-service by design).
 *
 * Also registers the three restricted permissions into every tenant's
 * tenant_permissions allowlist so an admin can still assign them to a
 * custom role from the Roles UI (same gap the payroll migration fixed).
 */
return new class extends Migration
{
    public function up(): void
    {
        $restrictedPermIds = DB::table('permissions')
            ->whereIn('name', ['leave.view_all', 'leave.review', 'leave.manage'])
            ->pluck('id');

        if ($restrictedPermIds->isEmpty()) {
            return;
        }

        $nonAdminRoleIds = DB::table('roles')->where('name', '!=', 'admin')->pluck('id');

        DB::table('role_permissions')
            ->whereIn('permission_id', $restrictedPermIds)
            ->whereIn('role_id', $nonAdminRoleIds)
            ->delete();

        $tenantIds = DB::table('tenants')->pluck('id');
        foreach ($tenantIds as $tenantId) {
            $rows = $restrictedPermIds->map(fn ($permId) => ['tenant_id' => $tenantId, 'permission_id' => $permId])->all();
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

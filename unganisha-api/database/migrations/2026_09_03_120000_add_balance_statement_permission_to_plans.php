<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * subscription_plan_permissions is a THIRD gate on top of role_permissions
 * and tenant_permissions — User::getPermissionNames() intersects a role's
 * permissions against its tenant's active plan's permission list. The
 * 2026_09_03_090200 migration granted the new Bank Balance Statement
 * permissions at the role/tenant level but never touched this table, so
 * every tenant on a paid plan still had it stripped out at request time
 * even though role_permissions/tenant_permissions both said yes.
 *
 * Add it to whichever plans already carry its sibling permission
 * (reports.system_records) — same tier as the existing System Records
 * Report, not the Starter plan.
 */
return new class extends Migration
{
    public function up(): void
    {
        $newPermIds = DB::table('permissions')
            ->whereIn('name', ['menu.report_balance_statement', 'reports.balance_statement'])
            ->pluck('id');

        $siblingPermId = DB::table('permissions')->where('name', 'reports.system_records')->value('id');
        if (!$siblingPermId) {
            throw new \RuntimeException('reports.system_records permission not found — cannot determine plan tier.');
        }

        $planIds = DB::table('subscription_plan_permissions')
            ->where('permission_id', $siblingPermId)
            ->pluck('subscription_plan_id');

        foreach ($planIds as $planId) {
            foreach ($newPermIds as $permId) {
                DB::table('subscription_plan_permissions')->insertOrIgnore([
                    'subscription_plan_id' => $planId,
                    'permission_id' => $permId,
                ]);
            }
        }
    }

    public function down(): void
    {
        $ids = DB::table('permissions')
            ->whereIn('name', ['menu.report_balance_statement', 'reports.balance_statement'])
            ->pluck('id');
        DB::table('subscription_plan_permissions')->whereIn('permission_id', $ids)->delete();
    }
};

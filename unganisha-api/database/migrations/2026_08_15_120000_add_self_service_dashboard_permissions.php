<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * MyAttendance/TotalDeductions/StaffPenalties ("My Attendance", "My Total
 * Deductions", "My Report Deductions") were the only Dashboard widgets with
 * no dashboard.* permission gate at all — every other widget follows that
 * convention. Adds the three permissions, blanket-granted to every existing
 * role/tenant so behavior is unchanged until a tenant explicitly restricts
 * them (same convention every other permission seed in this codebase uses).
 */
return new class extends Migration
{
    public function up(): void
    {
        $perms = [
            ['name' => 'dashboard.my_attendance', 'label' => 'View My Attendance Widget', 'category' => 'dashboard', 'group_name' => 'Dashboard'],
            ['name' => 'dashboard.my_total_deductions', 'label' => 'View My Total Deductions Widget', 'category' => 'dashboard', 'group_name' => 'Dashboard'],
            ['name' => 'dashboard.my_report_deductions', 'label' => 'View My Report Deductions Widget', 'category' => 'dashboard', 'group_name' => 'Dashboard'],
        ];

        $permIds = [];
        foreach ($perms as $perm) {
            $existing = DB::table('permissions')->where('name', $perm['name'])->first();
            if ($existing) {
                DB::table('permissions')->where('name', $perm['name'])->update($perm);
                $permIds[] = $existing->id;
            } else {
                $id = (string) Str::uuid();
                DB::table('permissions')->insert(array_merge(['id' => $id], $perm));
                $permIds[] = $id;
            }
        }

        $roleIds = DB::table('roles')->pluck('id');
        foreach ($roleIds as $roleId) {
            foreach ($permIds as $permId) {
                DB::table('role_permissions')->insertOrIgnore(['role_id' => $roleId, 'permission_id' => $permId]);
            }
        }

        $tenantIds = DB::table('tenants')->pluck('id');
        foreach ($tenantIds as $tenantId) {
            foreach ($permIds as $permId) {
                DB::table('tenant_permissions')->insertOrIgnore(['tenant_id' => $tenantId, 'permission_id' => $permId]);
            }
        }
    }

    public function down(): void
    {
        $ids = DB::table('permissions')->whereIn('name', [
            'dashboard.my_attendance', 'dashboard.my_total_deductions', 'dashboard.my_report_deductions',
        ])->pluck('id');

        DB::table('role_permissions')->whereIn('permission_id', $ids)->delete();
        DB::table('tenant_permissions')->whereIn('permission_id', $ids)->delete();
        DB::table('permissions')->whereIn('id', $ids)->delete();
    }
};

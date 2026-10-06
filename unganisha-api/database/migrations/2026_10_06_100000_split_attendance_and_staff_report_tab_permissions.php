<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Attendance used one umbrella permission (attendance.manage) for every tab and
 * every write, and Staff Reports tied its Report, Deductions and Settings tabs to
 * staff_reports.review. This gives each tab its own permission, and gives the
 * self-service writes (check-in/out, own explanation requests, leave requests,
 * penalty subscriptions) a permission too, so every create/update/delete path is
 * gated.
 *
 * Grants are copied from the permission each new one replaces, across all three
 * layers (role, tenant, subscription plan), so nobody loses access on deploy. The
 * self-service permissions are granted to every role because those actions were
 * open to all staff before.
 */
return new class extends Migration
{
    /** name => [label, group_name, grant source: 'attendance.manage'|'staff_reports.review'|'staff_reports.submit'|'*' (everyone)|null] */
    private array $perms = [
        // ── Attendance sidebar entry (the menu switch in Roles) ──
        'menu.attendance'       => ['Attendance menu', 'Navigation', ['attendance.manage'], 'menu'],
        // ── Attendance tabs ──
        'attendance.dashboard'  => ['View attendance dashboard & daily records', 'Attendance', ['attendance.manage'], null],
        'attendance.record'     => ['Record staff attendance', 'Attendance', ['attendance.manage'], null],
        'attendance.report'     => ['View & export attendance report', 'Attendance', ['attendance.manage'], null],
        'attendance.deductions' => ['Manage attendance deductions (waive / unwaive)', 'Attendance', ['attendance.manage'], null],
        'attendance.requests'   => ['Review staff explanation requests', 'Attendance', ['attendance.manage'], null],
        'attendance.import'     => ['Import attendance (iVMS sheets)', 'Attendance', ['attendance.manage'], null],
        'attendance.device'     => ['Manage attendance device & mappings', 'Attendance', ['attendance.manage'], null],
        'attendance.settings'   => ['Change attendance settings', 'Attendance', ['attendance.manage', 'staff_reports.review'], null],
        // ── Attendance self-service ──
        'attendance.checkin'    => ['Check in / check out on own attendance', 'Attendance', ['*'], null],
        'attendance.request'    => ['Submit own attendance explanation requests', 'Attendance', ['*'], null],
        // ── Staff Reports tabs ──
        'staff_reports.dashboard' => ['View staff reports dashboard', 'Staff Reports', ['staff_reports.submit'], null],
        'staff_reports.report'    => ['View & export staff report', 'Staff Reports', ['staff_reports.review'], null],
        'staff_reports.deductions' => ['Manage staff report deductions (waive / unwaive)', 'Staff Reports', ['staff_reports.review'], null],
        'staff_reports.settings'  => ['Change staff report settings, holidays & supervisors', 'Staff Reports', ['staff_reports.review'], null],
        // ── Leave self-service (employee subscriptions already require payroll.manage) ──
        'leave.request'         => ['Submit own leave requests', 'Leave', ['*'], null],
    ];

    public function up(): void
    {
        $roleIds = DB::table('roles')->pluck('id');
        $tenantIds = DB::table('tenants')->pluck('id');
        $planIds = DB::table('subscription_plans')->pluck('id');

        foreach ($this->perms as $name => [$label, $group, $sources, $category]) {
            $existing = DB::table('permissions')->where('name', $name)->first();
            $row = ['label' => $label, 'category' => $category ?? 'crud', 'group_name' => $group];
            if ($existing) {
                DB::table('permissions')->where('id', $existing->id)->update($row);
                $permId = $existing->id;
            } else {
                $permId = (string) Str::uuid();
                DB::table('permissions')->insert(array_merge(['id' => $permId, 'name' => $name], $row));
            }

            if (in_array('*', $sources, true)) {
                // Self-service: every role / tenant / plan keeps it.
                $this->grant('role_permissions', 'role_id', $roleIds, $permId);
                $this->grant('tenant_permissions', 'tenant_id', $tenantIds, $permId);
                $this->grant('subscription_plan_permissions', 'subscription_plan_id', $planIds, $permId);
                continue;
            }

            // Copy each source permission's grants, across the three layers.
            foreach ($sources as $source) {
                $sourceId = DB::table('permissions')->where('name', $source)->value('id');
                if (!$sourceId) {
                    continue;
                }
                foreach ([
                    ['role_permissions', 'role_id'],
                    ['tenant_permissions', 'tenant_id'],
                    ['subscription_plan_permissions', 'subscription_plan_id'],
                ] as [$table, $ownerCol]) {
                    $owners = DB::table($table)->where('permission_id', $sourceId)->pluck($ownerCol);
                    $this->grant($table, $ownerCol, $owners, $permId);
                }
            }
        }
    }

    public function down(): void
    {
        $ids = DB::table('permissions')->whereIn('name', array_keys($this->perms))->pluck('id');
        DB::table('role_permissions')->whereIn('permission_id', $ids)->delete();
        DB::table('tenant_permissions')->whereIn('permission_id', $ids)->delete();
        DB::table('subscription_plan_permissions')->whereIn('permission_id', $ids)->delete();
        DB::table('permissions')->whereIn('id', $ids)->delete();
    }

    private function grant(string $table, string $ownerCol, iterable $owners, string $permId): void
    {
        foreach ($owners as $ownerId) {
            DB::table($table)->insertOrIgnore([$ownerCol => $ownerId, 'permission_id' => $permId]);
        }
    }
};

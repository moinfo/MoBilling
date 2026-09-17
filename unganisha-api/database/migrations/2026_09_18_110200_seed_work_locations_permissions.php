<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

return new class extends Migration
{
    public function up(): void
    {
        $perms = [
            ['name' => 'menu.work_locations',   'label' => 'Work Locations menu',   'category' => 'menu', 'group_name' => 'Navigation'],
            ['name' => 'work_locations.read',   'label' => 'View work locations',   'category' => 'crud', 'group_name' => 'Work Locations'],
            ['name' => 'work_locations.create', 'label' => 'Create work locations', 'category' => 'crud', 'group_name' => 'Work Locations'],
            ['name' => 'work_locations.update', 'label' => 'Update work locations', 'category' => 'crud', 'group_name' => 'Work Locations'],
            ['name' => 'work_locations.delete', 'label' => 'Delete work locations', 'category' => 'crud', 'group_name' => 'Work Locations'],
        ];

        foreach ($perms as $perm) {
            $existing = DB::table('permissions')->where('name', $perm['name'])->first();
            if ($existing) {
                DB::table('permissions')->where('name', $perm['name'])->update($perm);
            } else {
                DB::table('permissions')->insert(array_merge(['id' => (string) Str::uuid()], $perm));
            }
        }

        $permIds = DB::table('permissions')->whereIn('name', array_column($perms, 'name'))->pluck('id');

        foreach (DB::table('roles')->pluck('id') as $roleId) {
            foreach ($permIds as $permId) {
                DB::table('role_permissions')->insertOrIgnore(['role_id' => $roleId, 'permission_id' => $permId]);
            }
        }
        foreach (DB::table('tenants')->pluck('id') as $tenantId) {
            foreach ($permIds as $permId) {
                DB::table('tenant_permissions')->insertOrIgnore(['tenant_id' => $tenantId, 'permission_id' => $permId]);
            }
        }
        foreach (DB::table('subscription_plans')->pluck('id') as $planId) {
            foreach ($permIds as $permId) {
                DB::table('subscription_plan_permissions')->insertOrIgnore(['subscription_plan_id' => $planId, 'permission_id' => $permId]);
            }
        }
    }

    public function down(): void
    {
        $names = [
            'menu.work_locations',
            'work_locations.read', 'work_locations.create', 'work_locations.update', 'work_locations.delete',
        ];
        $ids = DB::table('permissions')->whereIn('name', $names)->pluck('id');
        DB::table('role_permissions')->whereIn('permission_id', $ids)->delete();
        DB::table('tenant_permissions')->whereIn('permission_id', $ids)->delete();
        DB::table('subscription_plan_permissions')->whereIn('permission_id', $ids)->delete();
        DB::table('permissions')->whereIn('id', $ids)->delete();
    }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

return new class extends Migration
{
    public function up(): void
    {
        $perms = [
            ['name' => 'menu.system_record_expenses',    'label' => 'Withdraw Usage menu',       'category' => 'menu', 'group_name' => 'Navigation'],
            ['name' => 'system_record_expenses.read',    'label' => 'View withdraw usage',       'category' => 'crud', 'group_name' => 'System Records'],
            ['name' => 'system_record_expenses.create',  'label' => 'Record withdraw usage',     'category' => 'crud', 'group_name' => 'System Records'],
            ['name' => 'system_record_expenses.update',  'label' => 'Update withdraw usage',     'category' => 'crud', 'group_name' => 'System Records'],
            ['name' => 'system_record_expenses.delete',  'label' => 'Delete withdraw usage',     'category' => 'crud', 'group_name' => 'System Records'],
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
            'menu.system_record_expenses',
            'system_record_expenses.read', 'system_record_expenses.create',
            'system_record_expenses.update', 'system_record_expenses.delete',
        ];
        $ids = DB::table('permissions')->whereIn('name', $names)->pluck('id');
        DB::table('role_permissions')->whereIn('permission_id', $ids)->delete();
        DB::table('tenant_permissions')->whereIn('permission_id', $ids)->delete();
        DB::table('subscription_plan_permissions')->whereIn('permission_id', $ids)->delete();
        DB::table('permissions')->whereIn('id', $ids)->delete();
    }
};

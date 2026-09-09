<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

return new class extends Migration
{
    public function up(): void
    {
        $perms = [
            ['name' => 'menu.wifi_hotspot',       'label' => 'WiFi Hotspot menu',            'category' => 'menu', 'group_name' => 'Navigation'],
            ['name' => 'wifi_routers.read',        'label' => 'View WiFi routers',            'category' => 'crud', 'group_name' => 'WiFi Hotspot'],
            ['name' => 'wifi_routers.create',      'label' => 'Create WiFi routers',          'category' => 'crud', 'group_name' => 'WiFi Hotspot'],
            ['name' => 'wifi_routers.update',      'label' => 'Update WiFi routers',          'category' => 'crud', 'group_name' => 'WiFi Hotspot'],
            ['name' => 'wifi_routers.delete',      'label' => 'Delete WiFi routers',          'category' => 'crud', 'group_name' => 'WiFi Hotspot'],
            ['name' => 'wifi_plans.read',          'label' => 'View WiFi plans',              'category' => 'crud', 'group_name' => 'WiFi Hotspot'],
            ['name' => 'wifi_plans.create',        'label' => 'Create WiFi plans',            'category' => 'crud', 'group_name' => 'WiFi Hotspot'],
            ['name' => 'wifi_plans.update',        'label' => 'Update WiFi plans',            'category' => 'crud', 'group_name' => 'WiFi Hotspot'],
            ['name' => 'wifi_plans.delete',        'label' => 'Delete WiFi plans',            'category' => 'crud', 'group_name' => 'WiFi Hotspot'],
            ['name' => 'wifi_purchases.read',      'label' => 'View WiFi voucher purchases',  'category' => 'crud', 'group_name' => 'WiFi Hotspot'],
        ];

        foreach ($perms as $perm) {
            $existing = DB::table('permissions')->where('name', $perm['name'])->first();
            if ($existing) {
                DB::table('permissions')->where('name', $perm['name'])->update($perm);
            } else {
                DB::table('permissions')->insert(array_merge(['id' => (string) Str::uuid()], $perm));
            }
        }

        $names = array_column($perms, 'name');
        $permIds = DB::table('permissions')->whereIn('name', $names)->pluck('id');

        foreach (DB::table('roles')->pluck('id') as $roleId) {
            foreach ($permIds as $permId) {
                DB::table('role_permissions')->insertOrIgnore([
                    'role_id'       => $roleId,
                    'permission_id' => $permId,
                ]);
            }
        }

        foreach (DB::table('tenants')->pluck('id') as $tenantId) {
            foreach ($permIds as $permId) {
                DB::table('tenant_permissions')->insertOrIgnore([
                    'tenant_id'     => $tenantId,
                    'permission_id' => $permId,
                ]);
            }
        }

        // New feature area — also add to every subscription plan so it
        // isn't stripped out by the plan-permission ceiling
        // (see [[three-layer-permission-system]]).
        foreach (DB::table('subscription_plans')->pluck('id') as $planId) {
            foreach ($permIds as $permId) {
                DB::table('subscription_plan_permissions')->insertOrIgnore([
                    'subscription_plan_id' => $planId,
                    'permission_id'        => $permId,
                ]);
            }
        }
    }

    public function down(): void
    {
        $names = [
            'menu.wifi_hotspot',
            'wifi_routers.read', 'wifi_routers.create', 'wifi_routers.update', 'wifi_routers.delete',
            'wifi_plans.read', 'wifi_plans.create', 'wifi_plans.update', 'wifi_plans.delete',
            'wifi_purchases.read',
        ];
        $ids = DB::table('permissions')->whereIn('name', $names)->pluck('id');
        DB::table('role_permissions')->whereIn('permission_id', $ids)->delete();
        DB::table('tenant_permissions')->whereIn('permission_id', $ids)->delete();
        DB::table('subscription_plan_permissions')->whereIn('permission_id', $ids)->delete();
        DB::table('permissions')->whereIn('id', $ids)->delete();
    }
};

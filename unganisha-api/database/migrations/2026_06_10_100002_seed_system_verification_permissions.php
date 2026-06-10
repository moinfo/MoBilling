<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

return new class extends Migration
{
    public function up(): void
    {
        $perms = [
            // Menu items
            ['name' => 'menu.system_verifications', 'label' => 'System Verifications menu (admin)', 'category' => 'menu', 'group_name' => 'Navigation'],
            ['name' => 'menu.my_verifications',     'label' => 'My Verifications menu (staff)',    'category' => 'menu', 'group_name' => 'Navigation'],

            // Admin CRUD on the registered systems
            ['name' => 'system_verifications.read',   'label' => 'View system verifications',   'category' => 'crud', 'group_name' => 'System Verifications'],
            ['name' => 'system_verifications.create', 'label' => 'Register system verifications','category' => 'crud', 'group_name' => 'System Verifications'],
            ['name' => 'system_verifications.update', 'label' => 'Update system verifications', 'category' => 'crud', 'group_name' => 'System Verifications'],
            ['name' => 'system_verifications.delete', 'label' => 'Delete system verifications', 'category' => 'crud', 'group_name' => 'System Verifications'],

            // Reports (daily check-ins). Staff submits; admin reads all.
            ['name' => 'system_verification_reports.read',   'label' => 'View verification reports (all staff)', 'category' => 'crud', 'group_name' => 'System Verifications'],
            ['name' => 'system_verification_reports.submit', 'label' => 'Submit daily verification report',      'category' => 'crud', 'group_name' => 'System Verifications'],
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
    }

    public function down(): void
    {
        $names = [
            'menu.system_verifications', 'menu.my_verifications',
            'system_verifications.read', 'system_verifications.create', 'system_verifications.update', 'system_verifications.delete',
            'system_verification_reports.read', 'system_verification_reports.submit',
        ];
        $ids = DB::table('permissions')->whereIn('name', $names)->pluck('id');
        DB::table('role_permissions')->whereIn('permission_id', $ids)->delete();
        DB::table('tenant_permissions')->whereIn('permission_id', $ids)->delete();
        DB::table('permissions')->whereIn('id', $ids)->delete();
    }
};

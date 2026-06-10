<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

return new class extends Migration
{
    public function up(): void
    {
        $perms = [
            ['name' => 'menu.report_system_verifications', 'label' => 'System Verifications Report menu',  'category' => 'menu',    'group_name' => 'Navigation'],
            ['name' => 'reports.system_verifications',     'label' => 'View System Verifications report', 'category' => 'reports', 'group_name' => 'Reports'],
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

        // Admin-only report (it shows ALL staff completion rates)
        foreach (DB::table('roles')->where('name', 'admin')->pluck('id') as $roleId) {
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
        $names = ['menu.report_system_verifications', 'reports.system_verifications'];
        $ids = DB::table('permissions')->whereIn('name', $names)->pluck('id');
        DB::table('role_permissions')->whereIn('permission_id', $ids)->delete();
        DB::table('tenant_permissions')->whereIn('permission_id', $ids)->delete();
        DB::table('permissions')->whereIn('id', $ids)->delete();
    }
};

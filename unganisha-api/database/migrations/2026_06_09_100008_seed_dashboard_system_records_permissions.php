<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Each Dashboard widget has its own dashboard.* permission so it can be
 * shown/hidden independently of the underlying data-read permission.
 *
 * Two new permissions for the System Records dashboard cards:
 *   - dashboard.system_records_breakdown  (the per-system / per-property card)
 *   - dashboard.bank_account_breakdown    (the per-bank-account card)
 *
 * Granted to every existing role + tenant by default, matching the
 * open-by-default pattern of the original system records seeder. Tighten
 * via the Roles management UI as needed.
 */
return new class extends Migration
{
    public function up(): void
    {
        $perms = [
            ['name' => 'dashboard.system_records_breakdown', 'label' => 'Dashboard: System Records breakdown widget', 'category' => 'dashboard', 'group_name' => 'Dashboard'],
            ['name' => 'dashboard.bank_account_breakdown',   'label' => 'Dashboard: Bank Account breakdown widget',   'category' => 'dashboard', 'group_name' => 'Dashboard'],
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
        $names = ['dashboard.system_records_breakdown', 'dashboard.bank_account_breakdown'];
        $ids = DB::table('permissions')->whereIn('name', $names)->pluck('id');
        DB::table('role_permissions')->whereIn('permission_id', $ids)->delete();
        DB::table('tenant_permissions')->whereIn('permission_id', $ids)->delete();
        DB::table('permissions')->whereIn('id', $ids)->delete();
    }
};

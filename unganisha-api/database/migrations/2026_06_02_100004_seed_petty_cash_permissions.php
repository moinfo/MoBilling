<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

return new class extends Migration
{
    public function up(): void
    {
        $perms = [
            ['name' => 'menu.petty_cash',     'label' => 'Petty Cash menu',           'category' => 'menu', 'group_name' => 'Navigation'],
            ['name' => 'petty_cash.read',     'label' => 'View petty cash',           'category' => 'crud', 'group_name' => 'Petty Cash'],
            ['name' => 'petty_cash.topup',    'label' => 'Record petty cash top-up',  'category' => 'crud', 'group_name' => 'Petty Cash'],
            ['name' => 'petty_cash.reconcile','label' => 'Reconcile petty cash',      'category' => 'crud', 'group_name' => 'Petty Cash'],
        ];

        foreach ($perms as $perm) {
            $existing = DB::table('permissions')->where('name', $perm['name'])->first();
            if ($existing) {
                DB::table('permissions')->where('name', $perm['name'])->update($perm);
            } else {
                DB::table('permissions')->insert(array_merge(['id' => (string) Str::uuid()], $perm));
            }
        }

        $permIds = DB::table('permissions')
            ->where(fn ($q) => $q->where('name', 'like', 'petty_cash.%')->orWhere('name', 'menu.petty_cash'))
            ->pluck('id');

        // Grant to every existing role (matches the staff_targets seeder pattern)
        foreach (DB::table('roles')->pluck('id') as $roleId) {
            foreach ($permIds as $permId) {
                DB::table('role_permissions')->insertOrIgnore([
                    'role_id'       => $roleId,
                    'permission_id' => $permId,
                ]);
            }
        }

        // Grant to every tenant (matches the grant_missing_permissions pattern)
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
        $names = ['menu.petty_cash', 'petty_cash.read', 'petty_cash.topup', 'petty_cash.reconcile'];
        $ids = DB::table('permissions')->whereIn('name', $names)->pluck('id');
        DB::table('role_permissions')->whereIn('permission_id', $ids)->delete();
        DB::table('tenant_permissions')->whereIn('permission_id', $ids)->delete();
        DB::table('permissions')->whereIn('id', $ids)->delete();
    }
};

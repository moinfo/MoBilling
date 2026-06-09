<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Permissions for the new System Records feature plus its three supporting
 * reference CRUDs (Systems, Bank Accounts, System Properties).
 *
 * Granted to every existing role + tenant by default, matching the same
 * "open by default" pattern as the original petty cash seeder. Tighten via
 * the Roles management UI as needed.
 */
return new class extends Migration
{
    public function up(): void
    {
        $perms = [
            // Menu visibility
            ['name' => 'menu.systems',            'label' => 'Systems menu',             'category' => 'menu', 'group_name' => 'Navigation'],
            ['name' => 'menu.bank_accounts',      'label' => 'Bank Accounts menu',       'category' => 'menu', 'group_name' => 'Navigation'],
            ['name' => 'menu.system_properties',  'label' => 'System Properties menu',   'category' => 'menu', 'group_name' => 'Navigation'],
            ['name' => 'menu.system_records',     'label' => 'System Records menu',      'category' => 'menu', 'group_name' => 'Navigation'],

            // Systems CRUD
            ['name' => 'systems.read',     'label' => 'View systems',     'category' => 'crud', 'group_name' => 'Systems'],
            ['name' => 'systems.create',   'label' => 'Create systems',   'category' => 'crud', 'group_name' => 'Systems'],
            ['name' => 'systems.update',   'label' => 'Update systems',   'category' => 'crud', 'group_name' => 'Systems'],
            ['name' => 'systems.delete',   'label' => 'Delete systems',   'category' => 'crud', 'group_name' => 'Systems'],

            // Bank Accounts CRUD
            ['name' => 'bank_accounts.read',   'label' => 'View bank accounts',   'category' => 'crud', 'group_name' => 'Bank Accounts'],
            ['name' => 'bank_accounts.create', 'label' => 'Create bank accounts', 'category' => 'crud', 'group_name' => 'Bank Accounts'],
            ['name' => 'bank_accounts.update', 'label' => 'Update bank accounts', 'category' => 'crud', 'group_name' => 'Bank Accounts'],
            ['name' => 'bank_accounts.delete', 'label' => 'Delete bank accounts', 'category' => 'crud', 'group_name' => 'Bank Accounts'],

            // System Properties CRUD
            ['name' => 'system_properties.read',   'label' => 'View system properties',   'category' => 'crud', 'group_name' => 'System Properties'],
            ['name' => 'system_properties.create', 'label' => 'Create system properties', 'category' => 'crud', 'group_name' => 'System Properties'],
            ['name' => 'system_properties.update', 'label' => 'Update system properties', 'category' => 'crud', 'group_name' => 'System Properties'],
            ['name' => 'system_properties.delete', 'label' => 'Delete system properties', 'category' => 'crud', 'group_name' => 'System Properties'],

            // System Records CRUD
            ['name' => 'system_records.read',   'label' => 'View system records',   'category' => 'crud', 'group_name' => 'System Records'],
            ['name' => 'system_records.create', 'label' => 'Create system records', 'category' => 'crud', 'group_name' => 'System Records'],
            ['name' => 'system_records.update', 'label' => 'Update system records', 'category' => 'crud', 'group_name' => 'System Records'],
            ['name' => 'system_records.delete', 'label' => 'Delete system records', 'category' => 'crud', 'group_name' => 'System Records'],
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
            'menu.systems', 'menu.bank_accounts', 'menu.system_properties', 'menu.system_records',
            'systems.read', 'systems.create', 'systems.update', 'systems.delete',
            'bank_accounts.read', 'bank_accounts.create', 'bank_accounts.update', 'bank_accounts.delete',
            'system_properties.read', 'system_properties.create', 'system_properties.update', 'system_properties.delete',
            'system_records.read', 'system_records.create', 'system_records.update', 'system_records.delete',
        ];
        $ids = DB::table('permissions')->whereIn('name', $names)->pluck('id');
        DB::table('role_permissions')->whereIn('permission_id', $ids)->delete();
        DB::table('tenant_permissions')->whereIn('permission_id', $ids)->delete();
        DB::table('permissions')->whereIn('id', $ids)->delete();
    }
};

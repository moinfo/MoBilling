<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

return new class extends Migration
{
    public function up(): void
    {
        $perms = [
            ['name' => 'menu.served_customers',    'label' => 'Served Customers menu',        'category' => 'menu', 'group_name' => 'Navigation'],
            ['name' => 'served.read',              'label' => 'View served customers',         'category' => 'crud', 'group_name' => 'Served Customers'],
            ['name' => 'served.create',            'label' => 'Record served customer',        'category' => 'crud', 'group_name' => 'Served Customers'],
            ['name' => 'served.update',            'label' => 'Edit served customer record',   'category' => 'crud', 'group_name' => 'Served Customers'],
            ['name' => 'served.delete',            'label' => 'Delete served customer record', 'category' => 'crud', 'group_name' => 'Served Customers'],
            ['name' => 'served.settings',          'label' => 'Manage served services list',   'category' => 'crud', 'group_name' => 'Served Customers'],
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
            ->where(fn ($q) => $q->where('name', 'like', 'served.%')->orWhere('name', 'menu.served_customers'))
            ->pluck('id');

        $roleIds = DB::table('roles')->pluck('id');

        foreach ($roleIds as $roleId) {
            foreach ($permIds as $permId) {
                DB::table('role_permissions')->insertOrIgnore([
                    'role_id'       => $roleId,
                    'permission_id' => $permId,
                ]);
            }
        }
    }

    public function down(): void {}
};

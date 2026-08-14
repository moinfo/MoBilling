<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

return new class extends Migration
{
    public function up(): void
    {
        $perms = [
            ['name' => 'menu.employees',    'label' => 'Employees menu',           'category' => 'menu', 'group_name' => 'Navigation'],
            ['name' => 'employees.read',    'label' => 'View employee profiles',   'category' => 'crud', 'group_name' => 'Employees'],
            ['name' => 'employees.create',  'label' => 'Create employee profiles', 'category' => 'crud', 'group_name' => 'Employees'],
            ['name' => 'employees.update',  'label' => 'Update employee profiles', 'category' => 'crud', 'group_name' => 'Employees'],
            ['name' => 'employees.delete',  'label' => 'Delete employee profiles', 'category' => 'crud', 'group_name' => 'Employees'],
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
            ->where(fn ($q) => $q->where('name', 'like', 'employees.%')->orWhere('name', 'menu.employees'))
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

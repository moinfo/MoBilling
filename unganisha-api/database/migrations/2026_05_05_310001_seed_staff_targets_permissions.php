<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

return new class extends Migration
{
    public function up(): void
    {
        $perms = [
            ['name' => 'menu.staff_targets',      'label' => 'Staff Targets menu',                  'category' => 'menu', 'group_name' => 'Navigation'],
            ['name' => 'staff_targets.submit',    'label' => 'View own targets & self-report',       'category' => 'crud', 'group_name' => 'Staff Targets'],
            ['name' => 'staff_targets.manage',    'label' => 'Create & manage staff targets',        'category' => 'crud', 'group_name' => 'Staff Targets'],
            ['name' => 'staff_targets.verify',    'label' => 'Verify targets & confirm commissions', 'category' => 'crud', 'group_name' => 'Staff Targets'],
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
            ->where(fn ($q) => $q->where('name', 'like', 'staff_targets.%')->orWhere('name', 'menu.staff_targets'))
            ->pluck('id');

        foreach (DB::table('roles')->pluck('id') as $roleId) {
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
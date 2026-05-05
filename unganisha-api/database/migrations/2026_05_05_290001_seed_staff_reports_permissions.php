<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

return new class extends Migration
{
    public function up(): void
    {
        $perms = [
            ['name' => 'menu.staff_reports',     'label' => 'Staff Reports menu',           'category' => 'menu', 'group_name' => 'Navigation'],
            ['name' => 'staff_reports.submit',   'label' => 'Submit own staff reports',     'category' => 'crud', 'group_name' => 'Staff Reports'],
            ['name' => 'staff_reports.review',   'label' => 'Review & assess team reports', 'category' => 'crud', 'group_name' => 'Staff Reports'],
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
            ->where(fn ($q) => $q->where('name', 'like', 'staff_reports.%')->orWhere('name', 'menu.staff_reports'))
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

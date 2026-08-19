<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

return new class extends Migration
{
    public function up(): void
    {
        $perms = [
            ['name' => 'menu.leave',     'label' => 'Leave menu',                       'category' => 'menu', 'group_name' => 'Navigation'],
            ['name' => 'leave.submit',   'label' => 'Request own leave',                'category' => 'crud', 'group_name' => 'Leave'],
            ['name' => 'leave.review',   'label' => 'Approve/reject team leave requests', 'category' => 'crud', 'group_name' => 'Leave'],
            ['name' => 'leave.manage',   'label' => 'Manage leave types & balances',    'category' => 'crud', 'group_name' => 'Leave'],
            ['name' => 'leave.view_all', 'label' => 'View all leave requests (org-wide)', 'category' => 'crud', 'group_name' => 'Leave'],
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
            ->where(fn ($q) => $q->where('name', 'like', 'leave.%')->orWhere('name', 'menu.leave'))
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

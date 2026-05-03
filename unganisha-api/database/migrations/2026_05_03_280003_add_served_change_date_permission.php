<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

return new class extends Migration
{
    public function up(): void
    {
        $perm = [
            'name'       => 'served.change_date',
            'label'      => 'Change served date (allow backdating)',
            'category'   => 'crud',
            'group_name' => 'Served Customers',
        ];

        $existing = DB::table('permissions')->where('name', $perm['name'])->first();
        if (!$existing) {
            DB::table('permissions')->insert(array_merge(['id' => (string) Str::uuid()], $perm));
        }

        // Assign only to admin role by default (restrict backdating to managers)
        $permId = DB::table('permissions')->where('name', 'served.change_date')->value('id');
        $adminRoleId = DB::table('roles')->where('name', 'admin')->value('id');

        if ($permId && $adminRoleId) {
            DB::table('role_permissions')->insertOrIgnore([
                'role_id'       => $adminRoleId,
                'permission_id' => $permId,
            ]);
        }
    }

    public function down(): void {}
};

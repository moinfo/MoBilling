<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        $perms = [
            ['name' => 'social.read',    'label' => 'View social media posts'],
            ['name' => 'social.create',  'label' => 'Create social media posts'],
            ['name' => 'social.update',  'label' => 'Update social media posts'],
            ['name' => 'social.delete',  'label' => 'Delete social media posts'],
            ['name' => 'social.targets', 'label' => 'Manage social media targets'],
        ];

        foreach ($perms as $perm) {
            DB::table('permissions')->insertOrIgnore(['name' => $perm['name'], 'label' => $perm['label']]);
        }

        // Assign all social.* permissions to all roles
        $permIds = DB::table('permissions')->where('name', 'like', 'social.%')->pluck('id');
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

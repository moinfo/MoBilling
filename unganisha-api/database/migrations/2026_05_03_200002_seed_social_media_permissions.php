<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

return new class extends Migration
{
    public function up(): void
    {
        $perms = [
            ['name' => 'menu.social_media', 'label' => 'Social Media',               'category' => 'menu', 'group_name' => 'Navigation'],
            ['name' => 'social.read',        'label' => 'View social media posts',     'category' => 'crud', 'group_name' => 'Social Media'],
            ['name' => 'social.create',      'label' => 'Create social media posts',   'category' => 'crud', 'group_name' => 'Social Media'],
            ['name' => 'social.update',      'label' => 'Update social media posts',   'category' => 'crud', 'group_name' => 'Social Media'],
            ['name' => 'social.delete',      'label' => 'Delete social media posts',   'category' => 'crud', 'group_name' => 'Social Media'],
            ['name' => 'social.targets',     'label' => 'Manage social media targets', 'category' => 'crud', 'group_name' => 'Social Media'],
        ];

        foreach ($perms as $perm) {
            $existing = DB::table('permissions')->where('name', $perm['name'])->first();
            if ($existing) {
                DB::table('permissions')->where('name', $perm['name'])->update($perm);
            } else {
                DB::table('permissions')->insert(array_merge(['id' => (string) Str::uuid()], $perm));
            }
        }

        // Assign all social permissions to all roles
        $permIds = DB::table('permissions')
            ->where(fn ($q) => $q->where('name', 'like', 'social.%')->orWhere('name', 'menu.social_media'))
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

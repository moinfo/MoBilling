<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

return new class extends Migration
{
    public function up(): void
    {
        $perms = [
            ['name' => 'social.board',          'label' => 'View Social Media Board',            'category' => 'crud', 'group_name' => 'Social Media'],
            ['name' => 'social.design_work',    'label' => 'View Design Work Tab',               'category' => 'crud', 'group_name' => 'Social Media'],
            ['name' => 'social.content',        'label' => 'View Content & Posting Tab',         'category' => 'crud', 'group_name' => 'Social Media'],
            ['name' => 'social.qa',             'label' => 'View QA Review Tab',                 'category' => 'crud', 'group_name' => 'Social Media'],
            ['name' => 'social.client_designs', 'label' => 'View Client Designs Tab',            'category' => 'crud', 'group_name' => 'Social Media'],
            ['name' => 'social.settings',       'label' => 'Manage Platform Settings',           'category' => 'crud', 'group_name' => 'Social Media'],
        ];

        foreach ($perms as $perm) {
            $existing = DB::table('permissions')->where('name', $perm['name'])->first();
            if ($existing) {
                DB::table('permissions')->where('name', $perm['name'])->update($perm);
            } else {
                DB::table('permissions')->insert(array_merge(['id' => (string) Str::uuid()], $perm));
            }
        }

        // Assign all new permissions to every existing role
        $permIds = DB::table('permissions')
            ->whereIn('name', array_column($perms, 'name'))
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

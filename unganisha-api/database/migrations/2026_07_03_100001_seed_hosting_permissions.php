<?php

use App\Models\Permission;
use App\Models\Role;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    private array $permissions = [
        ['name' => 'menu.hosting',           'label' => 'Hosting Menu',                 'category' => 'menu', 'group_name' => 'Hosting'],
        ['name' => 'hosting.read',           'label' => 'View Hosting Accounts',        'category' => 'crud', 'group_name' => 'Hosting'],
        ['name' => 'hosting.create',         'label' => 'Provision Hosting Account',    'category' => 'crud', 'group_name' => 'Hosting'],
        ['name' => 'hosting.suspend',        'label' => 'Suspend/Unsuspend Hosting',    'category' => 'crud', 'group_name' => 'Hosting'],
        ['name' => 'hosting.terminate',      'label' => 'Terminate Hosting Account',    'category' => 'crud', 'group_name' => 'Hosting'],
        ['name' => 'hosting.change_package', 'label' => 'Change Hosting Package',       'category' => 'crud', 'group_name' => 'Hosting'],
        ['name' => 'hosting.sso',            'label' => 'Login to cPanel (SSO)',        'category' => 'crud', 'group_name' => 'Hosting'],
        ['name' => 'hosting.settings',       'label' => 'Manage Hosting Servers',       'category' => 'crud', 'group_name' => 'Hosting'],
    ];

    public function up(): void
    {
        foreach ($this->permissions as $data) {
            Permission::firstOrCreate(['name' => $data['name']], $data);
        }

        // Grant to every tenant's admin role (defensive, same pattern as WhatsApp perms).
        $ids = Permission::whereIn('name', array_column($this->permissions, 'name'))->pluck('id');
        foreach (Role::withoutGlobalScopes()->where('name', 'admin')->get() as $admin) {
            foreach ($ids as $permId) {
                DB::table('role_permissions')->insertOrIgnore([
                    'role_id'       => $admin->id,
                    'permission_id' => $permId,
                ]);
            }
        }
    }

    public function down(): void
    {
        Permission::whereIn('name', array_column($this->permissions, 'name'))->delete();
    }
};

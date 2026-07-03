<?php

use App\Models\Permission;
use App\Models\Role;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    private array $permissions = [
        ['name' => 'menu.domains',       'label' => 'Domains Menu',               'category' => 'menu', 'group_name' => 'Domains'],
        ['name' => 'domains.read',       'label' => 'View Domains',               'category' => 'crud', 'group_name' => 'Domains'],
        ['name' => 'domains.create',     'label' => 'Register Domain',            'category' => 'crud', 'group_name' => 'Domains'],
        ['name' => 'domains.renew',      'label' => 'Renew Domain',               'category' => 'crud', 'group_name' => 'Domains'],
        ['name' => 'domains.transfer',   'label' => 'Transfer Domain / AuthInfo', 'category' => 'crud', 'group_name' => 'Domains'],
        ['name' => 'domains.manage_dns', 'label' => 'Manage Nameservers/DNSSEC',  'category' => 'crud', 'group_name' => 'Domains'],
        ['name' => 'domains.settings',   'label' => 'Registrar Accounts & TLD Pricing', 'category' => 'crud', 'group_name' => 'Domains'],
    ];

    public function up(): void
    {
        foreach ($this->permissions as $data) {
            Permission::firstOrCreate(['name' => $data['name']], $data);
        }

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

<?php

use App\Models\Permission;
use App\Models\Role;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    private array $permissions = [
        ['name' => 'menu.tickets',   'label' => 'Support Tickets Menu',      'category' => 'menu', 'group_name' => 'Support'],
        ['name' => 'tickets.read',   'label' => 'View Support Tickets',      'category' => 'crud', 'group_name' => 'Support'],
        ['name' => 'tickets.reply',  'label' => 'Reply to Support Tickets',  'category' => 'crud', 'group_name' => 'Support'],
        ['name' => 'tickets.manage', 'label' => 'Assign/Close Tickets',      'category' => 'crud', 'group_name' => 'Support'],
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

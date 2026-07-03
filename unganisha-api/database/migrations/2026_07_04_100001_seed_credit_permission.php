<?php

use App\Models\Permission;
use App\Models\Role;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        Permission::firstOrCreate(['name' => 'credit.manage'], [
            'name' => 'credit.manage', 'label' => 'Manage Client Credit',
            'category' => 'crud', 'group_name' => 'Billing',
        ]);

        $permId = Permission::where('name', 'credit.manage')->value('id');
        foreach (Role::withoutGlobalScopes()->where('name', 'admin')->get() as $admin) {
            DB::table('role_permissions')->insertOrIgnore([
                'role_id' => $admin->id, 'permission_id' => $permId,
            ]);
        }
    }

    public function down(): void
    {
        Permission::where('name', 'credit.manage')->delete();
    }
};

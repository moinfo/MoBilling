<?php

use App\Models\Permission;
use App\Models\Role;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        Permission::firstOrCreate(['name' => 'whatsapp_contacts.view_all'], [
            'name'       => 'whatsapp_contacts.view_all',
            'label'      => 'View All WhatsApp Contacts (every user\'s)',
            'category'   => 'crud',
            'group_name' => 'WhatsApp',
        ]);

        $permId = Permission::where('name', 'whatsapp_contacts.view_all')->value('id');

        // Grant to every tenant's admin role. Non-admins only see their own
        // contacts until explicitly given this permission.
        foreach (Role::where('name', 'admin')->get() as $admin) {
            DB::table('role_permissions')->insertOrIgnore([
                'role_id'       => $admin->id,
                'permission_id' => $permId,
            ]);
        }
    }

    public function down(): void
    {
        Permission::where('name', 'whatsapp_contacts.view_all')->delete();
    }
};

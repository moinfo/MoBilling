<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use App\Models\Permission;
use App\Models\Role;

return new class extends Migration
{
    private array $permissions = [
        ['name' => 'menu.whatsapp',             'label' => 'WhatsApp Menu',               'category' => 'menu', 'group_name' => 'WhatsApp'],
        ['name' => 'whatsapp_contacts.read',    'label' => 'View WhatsApp Contacts',      'category' => 'crud', 'group_name' => 'WhatsApp'],
        ['name' => 'whatsapp_contacts.create',  'label' => 'Add WhatsApp Contact',        'category' => 'crud', 'group_name' => 'WhatsApp'],
        ['name' => 'whatsapp_contacts.update',  'label' => 'Edit WhatsApp Contact',       'category' => 'crud', 'group_name' => 'WhatsApp'],
        ['name' => 'whatsapp_contacts.delete',  'label' => 'Delete WhatsApp Contact',     'category' => 'crud', 'group_name' => 'WhatsApp'],
        ['name' => 'whatsapp_contacts.convert', 'label' => 'Convert Contact to Client',   'category' => 'crud', 'group_name' => 'WhatsApp'],
        ['name' => 'whatsapp_contacts.log',     'label' => 'Log WhatsApp Follow-up Call', 'category' => 'crud', 'group_name' => 'WhatsApp'],
        ['name' => 'whatsapp_campaigns.read',   'label' => 'View Ad Campaigns',           'category' => 'crud', 'group_name' => 'WhatsApp'],
        ['name' => 'whatsapp_campaigns.create', 'label' => 'Create Ad Campaign',          'category' => 'crud', 'group_name' => 'WhatsApp'],
        ['name' => 'whatsapp_campaigns.update', 'label' => 'Edit Ad Campaign',            'category' => 'crud', 'group_name' => 'WhatsApp'],
        ['name' => 'whatsapp_campaigns.delete', 'label' => 'Delete Ad Campaign',          'category' => 'crud', 'group_name' => 'WhatsApp'],
    ];

    public function up(): void
    {
        foreach ($this->permissions as $data) {
            Permission::firstOrCreate(['name' => $data['name']], $data);
        }

        // Grant all WhatsApp permissions to the admin role
        $admin = Role::where('name', 'admin')->first();
        if ($admin) {
            $ids = Permission::whereIn('name', array_column($this->permissions, 'name'))->pluck('id');
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

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        $now = now();
        $permissions = [
            ['id' => (string) \Illuminate\Support\Str::uuid(), 'name' => 'dashboard.whatsapp_contacts', 'label' => 'View WhatsApp Contacts Count', 'category' => 'dashboard', 'group_name' => 'Dashboard', 'created_at' => $now, 'updated_at' => $now],
            ['id' => (string) \Illuminate\Support\Str::uuid(), 'name' => 'dashboard.field_visits',      'label' => 'View Field Prospects Count',   'category' => 'dashboard', 'group_name' => 'Dashboard', 'created_at' => $now, 'updated_at' => $now],
            ['id' => (string) \Illuminate\Support\Str::uuid(), 'name' => 'dashboard.month_filter',     'label' => 'Use Dashboard Month Filter',   'category' => 'dashboard', 'group_name' => 'Dashboard', 'created_at' => $now, 'updated_at' => $now],
        ];

        DB::table('permissions')->insertOrIgnore($permissions);

        $adminRoles = DB::table('roles')->where('name', 'admin')->get(['id']);
        $permIds    = collect($permissions)->pluck('id');

        $pivots = [];
        foreach ($adminRoles as $role) {
            foreach ($permIds as $pid) {
                $pivots[] = ['role_id' => $role->id, 'permission_id' => $pid];
            }
        }
        if ($pivots) DB::table('role_permissions')->insertOrIgnore($pivots);
    }

    public function down(): void
    {
        $names = ['dashboard.whatsapp_contacts', 'dashboard.field_visits', 'dashboard.month_filter'];
        $ids = DB::table('permissions')->whereIn('name', $names)->pluck('id');
        DB::table('role_permissions')->whereIn('permission_id', $ids)->delete();
        DB::table('permissions')->whereIn('name', $names)->delete();
    }
};

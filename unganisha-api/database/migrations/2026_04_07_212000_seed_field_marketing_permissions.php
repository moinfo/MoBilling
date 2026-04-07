<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        $now = now();
        $permissions = [
            // Menu
            ['id' => (string) \Illuminate\Support\Str::uuid(), 'name' => 'menu.field_marketing', 'label' => 'Field Marketing Menu',     'category' => 'menu', 'group_name' => 'Field Marketing', 'created_at' => $now, 'updated_at' => $now],
            // Sessions
            ['id' => (string) \Illuminate\Support\Str::uuid(), 'name' => 'field_sessions.read',   'label' => 'View Field Sessions',      'category' => 'crud', 'group_name' => 'Field Marketing', 'created_at' => $now, 'updated_at' => $now],
            ['id' => (string) \Illuminate\Support\Str::uuid(), 'name' => 'field_sessions.create',  'label' => 'Create Field Sessions',    'category' => 'crud', 'group_name' => 'Field Marketing', 'created_at' => $now, 'updated_at' => $now],
            ['id' => (string) \Illuminate\Support\Str::uuid(), 'name' => 'field_sessions.update',  'label' => 'Update Field Sessions',    'category' => 'crud', 'group_name' => 'Field Marketing', 'created_at' => $now, 'updated_at' => $now],
            ['id' => (string) \Illuminate\Support\Str::uuid(), 'name' => 'field_sessions.delete',  'label' => 'Delete Field Sessions',    'category' => 'crud', 'group_name' => 'Field Marketing', 'created_at' => $now, 'updated_at' => $now],
            // Visits
            ['id' => (string) \Illuminate\Support\Str::uuid(), 'name' => 'field_visits.create',    'label' => 'Log Field Visits',         'category' => 'crud', 'group_name' => 'Field Marketing', 'created_at' => $now, 'updated_at' => $now],
            ['id' => (string) \Illuminate\Support\Str::uuid(), 'name' => 'field_visits.update',    'label' => 'Update Field Visits',      'category' => 'crud', 'group_name' => 'Field Marketing', 'created_at' => $now, 'updated_at' => $now],
            ['id' => (string) \Illuminate\Support\Str::uuid(), 'name' => 'field_visits.delete',    'label' => 'Delete Field Visits',      'category' => 'crud', 'group_name' => 'Field Marketing', 'created_at' => $now, 'updated_at' => $now],
            ['id' => (string) \Illuminate\Support\Str::uuid(), 'name' => 'field_visits.convert',   'label' => 'Convert Visit to Client',  'category' => 'crud', 'group_name' => 'Field Marketing', 'created_at' => $now, 'updated_at' => $now],
            // Targets
            ['id' => (string) \Illuminate\Support\Str::uuid(), 'name' => 'field_targets.read',     'label' => 'View Field Targets',       'category' => 'crud', 'group_name' => 'Field Marketing', 'created_at' => $now, 'updated_at' => $now],
            ['id' => (string) \Illuminate\Support\Str::uuid(), 'name' => 'field_targets.update',   'label' => 'Set Field Targets',        'category' => 'crud', 'group_name' => 'Field Marketing', 'created_at' => $now, 'updated_at' => $now],
        ];

        DB::table('permissions')->insertOrIgnore($permissions);

        // Grant all to admin role on every tenant
        $adminRoles = DB::table('roles')->where('name', 'admin')->get(['id']);
        $permIds    = DB::table('permissions')
            ->whereIn('name', array_column($permissions, 'name'))
            ->pluck('id');

        $pivots = [];
        foreach ($adminRoles as $role) {
            foreach ($permIds as $permId) {
                $pivots[] = ['role_id' => $role->id, 'permission_id' => $permId];
            }
        }

        if ($pivots) {
            DB::table('role_permissions')->insertOrIgnore($pivots);
        }
    }

    public function down(): void
    {
        $names = [
            'menu.field_marketing',
            'field_sessions.read', 'field_sessions.create', 'field_sessions.update', 'field_sessions.delete',
            'field_visits.create', 'field_visits.update', 'field_visits.delete', 'field_visits.convert',
            'field_targets.read', 'field_targets.update',
        ];

        $ids = DB::table('permissions')->whereIn('name', $names)->pluck('id');
        DB::table('role_permissions')->whereIn('permission_id', $ids)->delete();
        DB::table('permissions')->whereIn('name', $names)->delete();
    }
};

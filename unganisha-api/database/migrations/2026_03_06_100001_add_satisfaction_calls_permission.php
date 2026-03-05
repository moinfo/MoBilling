<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

return new class extends Migration
{
    public function up(): void
    {
        // 1. Create the permission
        $permId = Str::uuid()->toString();

        DB::table('permissions')->insert([
            'id' => $permId,
            'name' => 'menu.satisfaction_calls',
            'label' => 'Satisfaction Calls',
            'category' => 'menu',
            'group_name' => 'satisfaction_calls',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        // 2. Grant to all tenants
        $tenantIds = DB::table('tenants')->pluck('id');

        foreach ($tenantIds as $tenantId) {
            DB::table('tenant_permissions')->insert([
                'tenant_id' => $tenantId,
                'permission_id' => $permId,
            ]);

            // 3. Grant to all admin roles (is_admin = true)
            $adminRoleIds = DB::table('roles')
                ->where('tenant_id', $tenantId)
                ->where('name', 'admin')
                ->pluck('id');

            foreach ($adminRoleIds as $roleId) {
                DB::table('role_permissions')->insert([
                    'role_id' => $roleId,
                    'permission_id' => $permId,
                ]);
            }
        }
    }

    public function down(): void
    {
        $perm = DB::table('permissions')->where('name', 'menu.satisfaction_calls')->first();

        if ($perm) {
            DB::table('role_permissions')->where('permission_id', $perm->id)->delete();
            DB::table('tenant_permissions')->where('permission_id', $perm->id)->delete();
            DB::table('permissions')->where('id', $perm->id)->delete();
        }
    }
};

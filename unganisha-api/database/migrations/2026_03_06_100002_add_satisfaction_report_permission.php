<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

return new class extends Migration
{
    public function up(): void
    {
        // Idempotent for the same reason as 2026_03_06_100001: the
        // 2026_02_28_800005 seed migration's current content already
        // includes this permission (added there after this migration had
        // already run in production, where each only executes once
        // regardless of later file edits — but a fresh `migrate` replays
        // both in order).
        $existing = DB::table('permissions')->where('name', 'reports.satisfaction')->first();
        $permId = $existing->id ?? Str::uuid()->toString();

        if (!$existing) {
            DB::table('permissions')->insert([
                'id' => $permId,
                'name' => 'reports.satisfaction',
                'label' => 'Satisfaction Report',
                'category' => 'reports',
                'group_name' => 'satisfaction',
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }

        $tenantIds = DB::table('tenants')->pluck('id');

        foreach ($tenantIds as $tenantId) {
            DB::table('tenant_permissions')->insertOrIgnore([
                'tenant_id' => $tenantId,
                'permission_id' => $permId,
            ]);

            $adminRoleIds = DB::table('roles')
                ->where('tenant_id', $tenantId)
                ->where('name', 'admin')
                ->pluck('id');

            foreach ($adminRoleIds as $roleId) {
                DB::table('role_permissions')->insertOrIgnore([
                    'role_id' => $roleId,
                    'permission_id' => $permId,
                ]);
            }
        }
    }

    public function down(): void
    {
        $perm = DB::table('permissions')->where('name', 'reports.satisfaction')->first();

        if ($perm) {
            DB::table('role_permissions')->where('permission_id', $perm->id)->delete();
            DB::table('tenant_permissions')->where('permission_id', $perm->id)->delete();
            DB::table('permissions')->where('id', $perm->id)->delete();
        }
    }
};

<?php

use App\Models\Permission;
use App\Models\Role;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * "Approve Expenses" permission — lets a user approve/reject pending petty-cash
 * expenses. Granted to every tenant's allowlist and to admin roles by default.
 */
return new class extends Migration
{
    public function up(): void
    {
        $perm = Permission::firstOrCreate(
            ['name' => 'expenses.approve'],
            ['label' => 'Approve Expenses', 'category' => 'crud', 'group_name' => 'Expenses'],
        );

        // Allow it for every tenant.
        $tenantRows = DB::table('tenants')->pluck('id')
            ->map(fn ($tid) => ['tenant_id' => $tid, 'permission_id' => $perm->id])->all();
        if ($tenantRows) {
            DB::table('tenant_permissions')->insertOrIgnore($tenantRows);
        }

        // Grant to admin roles.
        $adminRoleIds = Role::withoutGlobalScopes()->where('name', 'admin')->pluck('id');
        $roleRows = $adminRoleIds->map(fn ($rid) => ['role_id' => $rid, 'permission_id' => $perm->id])->all();
        if ($roleRows) {
            DB::table('role_permissions')->insertOrIgnore($roleRows);
        }
    }

    public function down(): void
    {
        Permission::where('name', 'expenses.approve')->delete();
    }
};

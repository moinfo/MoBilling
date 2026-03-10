<?php

use App\Models\Permission;
use App\Models\Role;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        $perm = Permission::firstOrCreate(
            ['name' => 'client_subscriptions.renew'],
            ['label' => 'Renew / Update Expire Date', 'category' => 'crud', 'group_name' => 'Client Subscriptions']
        );

        // Auto-assign to roles that already have client_subscriptions.update
        $updatePerm = Permission::where('name', 'client_subscriptions.update')->first();
        if ($updatePerm) {
            $roles = Role::whereHas('permissions', function ($q) use ($updatePerm) {
                $q->where('permissions.id', $updatePerm->id);
            })->get();

            foreach ($roles as $role) {
                $role->permissions()->syncWithoutDetaching([$perm->id]);
            }

            // Also assign to tenant_permissions
            $tenantIds = DB::table('tenant_permissions')
                ->where('permission_id', $updatePerm->id)
                ->pluck('tenant_id');

            $inserts = [];
            foreach ($tenantIds as $tenantId) {
                $inserts[] = ['tenant_id' => $tenantId, 'permission_id' => $perm->id];
            }

            if (!empty($inserts)) {
                DB::table('tenant_permissions')->insertOrIgnore($inserts);
            }
        }
    }

    public function down(): void
    {
        Permission::where('name', 'client_subscriptions.renew')->delete();
    }
};

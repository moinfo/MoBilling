<?php

use App\Models\Permission;
use App\Models\Role;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        $perms = [
            ['name' => 'clients.portal_login', 'label' => 'Login as Client (Portal)', 'category' => 'crud', 'group_name' => 'Clients'],
            ['name' => 'clients.portal_password', 'label' => 'Change Client Portal Password', 'category' => 'crud', 'group_name' => 'Clients'],
        ];

        $updatePerm = Permission::where('name', 'clients.update')->first();

        foreach ($perms as $permData) {
            $perm = Permission::firstOrCreate(
                ['name' => $permData['name']],
                $permData
            );

            // Auto-assign to roles that have clients.update
            if ($updatePerm) {
                $roles = Role::whereHas('permissions', fn ($q) => $q->where('permissions.id', $updatePerm->id))->get();
                foreach ($roles as $role) {
                    $role->permissions()->syncWithoutDetaching([$perm->id]);
                }

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
    }

    public function down(): void
    {
        Permission::whereIn('name', ['clients.portal_login', 'clients.portal_password'])->delete();
    }
};

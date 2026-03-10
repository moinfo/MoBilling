<?php

use App\Models\Permission;
use App\Models\Role;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    private array $permissions = [
        ['name' => 'client_profile.total_invoiced', 'label' => 'View Total Invoiced', 'category' => 'crud', 'group_name' => 'Client Profile'],
        ['name' => 'client_profile.total_paid', 'label' => 'View Total Paid', 'category' => 'crud', 'group_name' => 'Client Profile'],
        ['name' => 'client_profile.balance_due', 'label' => 'View Balance Due', 'category' => 'crud', 'group_name' => 'Client Profile'],
        ['name' => 'client_profile.active_subscriptions', 'label' => 'View Active Subscriptions', 'category' => 'crud', 'group_name' => 'Client Profile'],
        ['name' => 'client_profile.subscription_value', 'label' => 'View Subscription Value', 'category' => 'crud', 'group_name' => 'Client Profile'],
        ['name' => 'client_profile.subscription_price', 'label' => 'View Subscription Price', 'category' => 'crud', 'group_name' => 'Client Profile'],
    ];

    public function up(): void
    {
        $permIds = [];
        foreach ($this->permissions as $perm) {
            $p = Permission::firstOrCreate(['name' => $perm['name']], $perm);
            $permIds[] = $p->id;
        }

        // Auto-assign to roles that have menu.clients
        $clientsPerm = Permission::where('name', 'menu.clients')->first();
        if ($clientsPerm) {
            $roles = Role::whereHas('permissions', function ($q) use ($clientsPerm) {
                $q->where('permissions.id', $clientsPerm->id);
            })->get();

            foreach ($roles as $role) {
                $role->permissions()->syncWithoutDetaching($permIds);
            }

            // Also assign to tenant_permissions
            $tenantIds = DB::table('tenant_permissions')
                ->where('permission_id', $clientsPerm->id)
                ->pluck('tenant_id');

            $inserts = [];
            foreach ($tenantIds as $tenantId) {
                foreach ($permIds as $permId) {
                    $inserts[] = ['tenant_id' => $tenantId, 'permission_id' => $permId];
                }
            }

            if (!empty($inserts)) {
                DB::table('tenant_permissions')->insertOrIgnore($inserts);
            }
        }
    }

    public function down(): void
    {
        $names = array_column($this->permissions, 'name');
        Permission::whereIn('name', $names)->delete();
    }
};

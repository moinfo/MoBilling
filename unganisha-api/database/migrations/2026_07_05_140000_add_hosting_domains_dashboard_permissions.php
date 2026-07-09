<?php

use App\Models\Permission;
use App\Models\Role;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Give the dashboard "Hosting & Domains" section its own dashboard.* toggles
 * (like every other widget) instead of piggybacking on the menu permissions.
 * To preserve current behaviour, each new permission is granted to every role
 * and tenant that already has the matching menu.* permission.
 */
return new class extends Migration
{
    private array $map = [
        'dashboard.hosting' => ['label' => 'View Hosting Summary', 'source' => 'menu.hosting'],
        'dashboard.domains' => ['label' => 'View Domains Summary', 'source' => 'menu.domains'],
        'dashboard.tickets' => ['label' => 'View Open Tickets Summary', 'source' => 'menu.tickets'],
    ];

    public function up(): void
    {
        foreach ($this->map as $name => $meta) {
            $perm = Permission::firstOrCreate(
                ['name' => $name],
                ['label' => $meta['label'], 'category' => 'dashboard', 'group_name' => 'Dashboard'],
            );

            $source = Permission::where('name', $meta['source'])->first();
            if (!$source) {
                continue;
            }

            // Roles that currently have the menu permission keep seeing the cards.
            Role::whereHas('permissions', fn ($q) => $q->where('permissions.id', $source->id))
                ->get()
                ->each(fn ($role) => $role->permissions()->syncWithoutDetaching([$perm->id]));

            // Tenants allowed the menu permission are allowed the dashboard one.
            $tenantIds = DB::table('tenant_permissions')
                ->where('permission_id', $source->id)
                ->pluck('tenant_id');

            $rows = $tenantIds->map(fn ($tid) => ['tenant_id' => $tid, 'permission_id' => $perm->id])->all();
            if ($rows) {
                DB::table('tenant_permissions')->insertOrIgnore($rows);
            }
        }
    }

    public function down(): void
    {
        Permission::whereIn('name', array_keys($this->map))->delete();
    }
};

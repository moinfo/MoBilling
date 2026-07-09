<?php

use App\Models\Permission;
use App\Models\Role;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Remediation from the permissions audit:
 *  1. Seed two permissions that code references but were never created
 *     (documents.extend_due_date, field_visits.log) — their features were
 *     dead for every non-super-admin.
 *  2. Fix reports.satisfaction's group_name typo (satisfaction -> Reports).
 *  3. Catch-up: grant EVERY permission to EVERY tenant's allowlist, matching
 *     what RegisterController already does for new tenants. Closes the 26-
 *     permission gap across existing tenants AND the "role re-save strips
 *     unallowed perms" data-loss trap (once allowed, they can't be stripped).
 *  4. Give the two new permissions to each tenant's admin role so admins keep
 *     the capability immediately.
 */
return new class extends Migration
{
    private array $newPerms = [
        ['name' => 'documents.extend_due_date', 'label' => 'Extend Invoice Due Date', 'category' => 'crud', 'group_name' => 'Documents'],
        ['name' => 'field_visits.log', 'label' => 'Log Field Visit Call', 'category' => 'crud', 'group_name' => 'Field Marketing'],
    ];

    public function up(): void
    {
        // 1. Seed the missing permissions
        $newIds = [];
        foreach ($this->newPerms as $p) {
            $newIds[] = Permission::firstOrCreate(['name' => $p['name']], $p)->id;
        }

        // 2. Fix the metadata typo
        Permission::where('name', 'reports.satisfaction')->update(['group_name' => 'Reports']);

        // 3. Catch-up: every permission into every tenant's allowlist
        $allPermIds = Permission::pluck('id');
        $tenantIds = DB::table('tenants')->pluck('id');
        foreach ($tenantIds as $tid) {
            $rows = $allPermIds->map(fn ($pid) => ['tenant_id' => $tid, 'permission_id' => $pid])->all();
            foreach (array_chunk($rows, 500) as $chunk) {
                DB::table('tenant_permissions')->insertOrIgnore($chunk);
            }
        }

        // 4. Give the two new capabilities to every admin role (all tenants)
        $adminRoleIds = Role::withoutGlobalScopes()->where('name', 'admin')->pluck('id');
        $roleRows = [];
        foreach ($adminRoleIds as $rid) {
            foreach ($newIds as $pid) {
                $roleRows[] = ['role_id' => $rid, 'permission_id' => $pid];
            }
        }
        if ($roleRows) {
            DB::table('role_permissions')->insertOrIgnore($roleRows);
        }
    }

    public function down(): void
    {
        // Only reverse the seed of the two new permissions; the backfill is
        // intentionally left (it matches new-tenant behaviour).
        Permission::whereIn('name', array_column($this->newPerms, 'name'))->delete();
    }
};

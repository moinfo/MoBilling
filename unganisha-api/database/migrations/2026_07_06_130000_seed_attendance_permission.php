<?php

use App\Models\Permission;
use App\Models\Role;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Permission for the staff member who records everyone's attendance. Seeded
 * and propagated to every tenant's allowlist + admin roles (so it's assignable
 * immediately, per the propagation lesson).
 */
return new class extends Migration
{
    public function up(): void
    {
        $perm = Permission::firstOrCreate(
            ['name' => 'attendance.manage'],
            ['label' => 'Record staff attendance', 'category' => 'crud', 'group_name' => 'Attendance'],
        );

        // Every tenant may assign it.
        $rows = DB::table('tenants')->pluck('id')
            ->map(fn ($tid) => ['tenant_id' => $tid, 'permission_id' => $perm->id])->all();
        if ($rows) {
            DB::table('tenant_permissions')->insertOrIgnore($rows);
        }

        // Give it to existing admin roles.
        $adminRoleIds = Role::withoutGlobalScopes()->where('name', 'admin')->pluck('id');
        $roleRows = $adminRoleIds->map(fn ($rid) => ['role_id' => $rid, 'permission_id' => $perm->id])->all();
        if ($roleRows) {
            DB::table('role_permissions')->insertOrIgnore($roleRows);
        }
    }

    public function down(): void
    {
        Permission::where('name', 'attendance.manage')->delete();
    }
};

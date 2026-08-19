<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * PettyCashTransaction already uses SoftDeletes (and generateReference()
 * already accounts for trashed rows so numbers aren't recycled), but no
 * route ever exposed a delete action — only top-ups/returns entered in
 * error should be removable, never reconciliation-generated adjustments
 * (deleting one would silently desync the ledger from its reconciliation
 * record). Blanket-granted to every existing role/tenant, same convention
 * every permission seed in this codebase uses.
 */
return new class extends Migration
{
    public function up(): void
    {
        $existing = DB::table('permissions')->where('name', 'petty_cash.delete')->first();
        $permId = $existing?->id;
        if (!$permId) {
            $permId = (string) Str::uuid();
            DB::table('permissions')->insert([
                'id' => $permId, 'name' => 'petty_cash.delete', 'label' => 'Delete petty cash transaction',
                'category' => 'crud', 'group_name' => 'Petty Cash',
            ]);
        }

        $roleIds = DB::table('roles')->pluck('id');
        foreach ($roleIds as $roleId) {
            DB::table('role_permissions')->insertOrIgnore(['role_id' => $roleId, 'permission_id' => $permId]);
        }

        $tenantIds = DB::table('tenants')->pluck('id');
        foreach ($tenantIds as $tenantId) {
            DB::table('tenant_permissions')->insertOrIgnore(['tenant_id' => $tenantId, 'permission_id' => $permId]);
        }
    }

    public function down(): void
    {
        $permId = DB::table('permissions')->where('name', 'petty_cash.delete')->value('id');
        if ($permId) {
            DB::table('role_permissions')->where('permission_id', $permId)->delete();
            DB::table('tenant_permissions')->where('permission_id', $permId)->delete();
            DB::table('permissions')->where('id', $permId)->delete();
        }
    }
};

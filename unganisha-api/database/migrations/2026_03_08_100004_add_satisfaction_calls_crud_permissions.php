<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Add granular CRUD permissions for satisfaction calls:
 * log, assign, reschedule, cancel.
 */
return new class extends Migration
{
    private array $perms = [
        ['name' => 'satisfaction_calls.log',        'label' => 'Log Call',        'category' => 'crud', 'group_name' => 'Satisfaction Calls'],
        ['name' => 'satisfaction_calls.assign',     'label' => 'Assign Call',     'category' => 'crud', 'group_name' => 'Satisfaction Calls'],
        ['name' => 'satisfaction_calls.reschedule', 'label' => 'Reschedule Call', 'category' => 'crud', 'group_name' => 'Satisfaction Calls'],
        ['name' => 'satisfaction_calls.cancel',     'label' => 'Cancel Call',     'category' => 'crud', 'group_name' => 'Satisfaction Calls'],
    ];

    public function up(): void
    {
        // Insert permissions
        foreach ($this->perms as $perm) {
            if (!DB::table('permissions')->where('name', $perm['name'])->exists()) {
                DB::table('permissions')->insert(array_merge(['id' => Str::uuid()->toString()], $perm));
            }
        }

        $permIds = DB::table('permissions')
            ->whereIn('name', array_column($this->perms, 'name'))
            ->pluck('id')
            ->toArray();

        // Grant to all tenants
        $tenantIds = DB::table('tenants')->pluck('id')->toArray();
        foreach ($tenantIds as $tid) {
            $existing = DB::table('tenant_permissions')
                ->where('tenant_id', $tid)
                ->whereIn('permission_id', $permIds)
                ->pluck('permission_id')->toArray();

            $toInsert = array_diff($permIds, $existing);
            if (!empty($toInsert)) {
                DB::table('tenant_permissions')->insert(
                    array_map(fn ($pid) => ['tenant_id' => $tid, 'permission_id' => $pid], $toInsert)
                );
            }
        }

        // Grant to all admin roles
        $adminRoles = DB::table('roles')->where('name', 'admin')->pluck('id')->toArray();
        foreach ($adminRoles as $roleId) {
            $existing = DB::table('role_permissions')
                ->where('role_id', $roleId)
                ->whereIn('permission_id', $permIds)
                ->pluck('permission_id')->toArray();

            $toInsert = array_diff($permIds, $existing);
            if (!empty($toInsert)) {
                DB::table('role_permissions')->insert(
                    array_map(fn ($pid) => ['role_id' => $roleId, 'permission_id' => $pid], $toInsert)
                );
            }
        }
    }

    public function down(): void
    {
        $names = array_column($this->perms, 'name');
        $ids = DB::table('permissions')->whereIn('name', $names)->pluck('id')->toArray();
        DB::table('role_permissions')->whereIn('permission_id', $ids)->delete();
        DB::table('tenant_permissions')->whereIn('permission_id', $ids)->delete();
        DB::table('permissions')->whereIn('name', $names)->delete();
    }
};

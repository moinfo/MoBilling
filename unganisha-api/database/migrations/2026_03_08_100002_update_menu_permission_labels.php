<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * 1. Add missing menu permissions: Broadcast, Subscription, Roles, Settings.
 * 2. Update existing labels to match sidebar names.
 * 3. Grant new permissions to the default "admin" role so admins keep full access.
 */
return new class extends Migration
{
    public function up(): void
    {
        // --- 1. Add missing menu permissions ---
        $newPerms = [
            ['name' => 'menu.broadcast',    'label' => 'Broadcast',    'category' => 'menu', 'group_name' => 'Other'],
            ['name' => 'menu.subscription', 'label' => 'Subscription', 'category' => 'menu', 'group_name' => 'Other'],
            ['name' => 'menu.roles',        'label' => 'Roles',        'category' => 'menu', 'group_name' => 'Other'],
            ['name' => 'menu.settings',     'label' => 'Settings',     'category' => 'menu', 'group_name' => 'Other'],
        ];

        foreach ($newPerms as $perm) {
            // Only insert if not already present
            if (!DB::table('permissions')->where('name', $perm['name'])->exists()) {
                DB::table('permissions')->insert(array_merge(['id' => Str::uuid()->toString()], $perm));
            }
        }

        // --- 2. Update existing labels to match sidebar ---
        $labels = [
            'menu.statutories'          => 'Obligations & Schedule',
            'menu.statutory_bills'      => 'Bills',
            'menu.bill_categories'      => 'Categories',
            'menu.payments_out'         => 'Payment History',
            'menu.payments_in'          => 'Payments',
            'menu.client_subscriptions' => 'Subscriptions',
        ];

        foreach ($labels as $name => $label) {
            DB::table('permissions')
                ->where('name', $name)
                ->update(['label' => $label]);
        }

        // --- 3. Grant new perms to all tenants (tenant-level allowance) ---
        $newPermIds = DB::table('permissions')
            ->whereIn('name', array_column($newPerms, 'name'))
            ->pluck('id')
            ->toArray();

        $tenantIds = DB::table('tenants')->pluck('id')->toArray();

        foreach ($tenantIds as $tenantId) {
            $existing = DB::table('tenant_permissions')
                ->where('tenant_id', $tenantId)
                ->whereIn('permission_id', $newPermIds)
                ->pluck('permission_id')
                ->toArray();

            $toInsert = array_diff($newPermIds, $existing);

            if (!empty($toInsert)) {
                DB::table('tenant_permissions')->insert(
                    array_map(fn ($pid) => [
                        'tenant_id'     => $tenantId,
                        'permission_id' => $pid,
                    ], $toInsert)
                );
            }
        }

        // --- 4. Grant new perms to all admin roles ---
        $adminRoles = DB::table('roles')
            ->where('name', 'admin')
            ->pluck('id')
            ->toArray();

        foreach ($adminRoles as $roleId) {
            $existing = DB::table('role_permissions')
                ->where('role_id', $roleId)
                ->whereIn('permission_id', $newPermIds)
                ->pluck('permission_id')
                ->toArray();

            $toInsert = array_diff($newPermIds, $existing);

            if (!empty($toInsert)) {
                DB::table('role_permissions')->insert(
                    array_map(fn ($pid) => [
                        'role_id'       => $roleId,
                        'permission_id' => $pid,
                    ], $toInsert)
                );
            }
        }
    }

    public function down(): void
    {
        // Remove the new permissions from all tables
        $names = ['menu.broadcast', 'menu.subscription', 'menu.roles', 'menu.settings'];
        $ids = DB::table('permissions')->whereIn('name', $names)->pluck('id')->toArray();
        DB::table('role_permissions')->whereIn('permission_id', $ids)->delete();
        DB::table('tenant_permissions')->whereIn('permission_id', $ids)->delete();
        DB::table('permissions')->whereIn('name', $names)->delete();

        // Revert labels
        $labels = [
            'menu.statutories'          => 'Statutory Obligations',
            'menu.statutory_bills'      => 'Statutory Bills',
            'menu.bill_categories'      => 'Bill Categories',
            'menu.payments_out'         => 'Payment History',
            'menu.payments_in'          => 'Payments Received',
            'menu.client_subscriptions' => 'Client Subscriptions',
        ];

        foreach ($labels as $name => $label) {
            DB::table('permissions')
                ->where('name', $name)
                ->update(['label' => $label]);
        }
    }
};

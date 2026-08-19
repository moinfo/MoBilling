<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Four Billing sub-nav items shared a single permission with something
 * else, so there was no way to hide one without also hiding its sibling:
 * "Portal Users" reused clients.update (shared with client-editing
 * generally), and "Product Add-ons"/"Configurable Options"/
 * "Promotions & Coupons" all reused menu.products (shared with
 * "Products & Services" itself). Splits each into its own nav-only
 * permission, granted to exactly the roles that already had the shared
 * one — so visibility is unchanged everywhere until a tenant explicitly
 * narrows it. Backend route authorization for these features is
 * untouched (still clients.update / products.*) — this only affects
 * whether the nav link itself renders.
 */
return new class extends Migration
{
    private const MAP = [
        'menu.portal_users' => ['source' => 'clients.update', 'label' => 'Portal Users menu', 'category' => 'menu', 'group_name' => 'Billing'],
        'menu.product_addons' => ['source' => 'menu.products', 'label' => 'Product Add-ons menu', 'category' => 'menu', 'group_name' => 'Billing'],
        'menu.config_options' => ['source' => 'menu.products', 'label' => 'Configurable Options menu', 'category' => 'menu', 'group_name' => 'Billing'],
        'menu.coupons' => ['source' => 'menu.products', 'label' => 'Promotions / Coupons menu', 'category' => 'menu', 'group_name' => 'Billing'],
    ];

    public function up(): void
    {
        foreach (self::MAP as $newName => $meta) {
            $sourceId = DB::table('permissions')->where('name', $meta['source'])->value('id');
            if (!$sourceId) {
                continue;
            }

            $newId = DB::table('permissions')->where('name', $newName)->value('id');
            if (!$newId) {
                $newId = (string) Str::uuid();
                DB::table('permissions')->insert([
                    'id' => $newId, 'name' => $newName, 'label' => $meta['label'],
                    'category' => $meta['category'], 'group_name' => $meta['group_name'],
                ]);
            }

            $roleIds = DB::table('role_permissions')->where('permission_id', $sourceId)->pluck('role_id');
            foreach ($roleIds as $roleId) {
                DB::table('role_permissions')->insertOrIgnore(['role_id' => $roleId, 'permission_id' => $newId]);
            }

            $tenantIds = DB::table('tenant_permissions')->where('permission_id', $sourceId)->pluck('tenant_id');
            foreach ($tenantIds as $tenantId) {
                DB::table('tenant_permissions')->insertOrIgnore(['tenant_id' => $tenantId, 'permission_id' => $newId]);
            }
        }
    }

    public function down(): void
    {
        $ids = DB::table('permissions')->whereIn('name', array_keys(self::MAP))->pluck('id');
        DB::table('role_permissions')->whereIn('permission_id', $ids)->delete();
        DB::table('tenant_permissions')->whereIn('permission_id', $ids)->delete();
        DB::table('permissions')->whereIn('id', $ids)->delete();
    }
};

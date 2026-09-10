<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/** Lets tenant staff block/unblock a misbehaving customer's voucher — see WifiVoucherPurchaseController::block()/unblock(). */
return new class extends Migration
{
    public function up(): void
    {
        $perm = ['name' => 'wifi_purchases.update', 'label' => 'Block/unblock WiFi vouchers', 'category' => 'crud', 'group_name' => 'WiFi Hotspot'];

        $existing = DB::table('permissions')->where('name', $perm['name'])->first();
        if ($existing) {
            DB::table('permissions')->where('name', $perm['name'])->update($perm);
            $permId = $existing->id;
        } else {
            $permId = (string) Str::uuid();
            DB::table('permissions')->insert(array_merge(['id' => $permId], $perm));
        }

        foreach (DB::table('roles')->pluck('id') as $roleId) {
            DB::table('role_permissions')->insertOrIgnore(['role_id' => $roleId, 'permission_id' => $permId]);
        }

        foreach (DB::table('tenants')->pluck('id') as $tenantId) {
            DB::table('tenant_permissions')->insertOrIgnore(['tenant_id' => $tenantId, 'permission_id' => $permId]);
        }

        foreach (DB::table('subscription_plans')->pluck('id') as $planId) {
            DB::table('subscription_plan_permissions')->insertOrIgnore(['subscription_plan_id' => $planId, 'permission_id' => $permId]);
        }
    }

    public function down(): void
    {
        $id = DB::table('permissions')->where('name', 'wifi_purchases.update')->value('id');
        if ($id) {
            DB::table('role_permissions')->where('permission_id', $id)->delete();
            DB::table('tenant_permissions')->where('permission_id', $id)->delete();
            DB::table('subscription_plan_permissions')->where('permission_id', $id)->delete();
            DB::table('permissions')->where('id', $id)->delete();
        }
    }
};

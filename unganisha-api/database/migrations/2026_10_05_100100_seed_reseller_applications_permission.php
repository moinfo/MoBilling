<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Staff review/approve/reject/provision of white-label reseller applications,
 * plus staff-confirmed reseller-tenant wallet top-ups — both create/move real
 * money and a whole new paying tenant, so this stays admin-only. All three
 * layers (see three-layer permission system). No sufficiently-scoped existing
 * permission fits: clients.update/create are about the applicant's OWN
 * client record, not spinning up a new tenant.
 */
return new class extends Migration
{
    private array $perms = [
        ['name' => 'reseller_applications.manage', 'label' => 'Review, approve, provision reseller applications & confirm reseller wallet top-ups', 'category' => 'crud', 'group_name' => 'Reseller Applications'],
    ];

    public function up(): void
    {
        $adminRoleIds = DB::table('roles')->where('name', 'admin')->pluck('id');
        foreach ($this->perms as $perm) {
            $existing = DB::table('permissions')->where('name', $perm['name'])->first();
            if ($existing) {
                DB::table('permissions')->where('name', $perm['name'])->update($perm);
                $id = $existing->id;
            } else {
                $id = (string) Str::uuid();
                DB::table('permissions')->insert(array_merge(['id' => $id], $perm));
            }
            foreach ($adminRoleIds as $roleId) {
                DB::table('role_permissions')->insertOrIgnore(['role_id' => $roleId, 'permission_id' => $id]);
            }
            foreach (DB::table('tenants')->pluck('id') as $tid) {
                DB::table('tenant_permissions')->insertOrIgnore(['tenant_id' => $tid, 'permission_id' => $id]);
            }
            foreach (DB::table('subscription_plans')->pluck('id') as $pid) {
                DB::table('subscription_plan_permissions')->insertOrIgnore(['subscription_plan_id' => $pid, 'permission_id' => $id]);
            }
        }
    }

    public function down(): void
    {
        foreach ($this->perms as $perm) {
            $id = DB::table('permissions')->where('name', $perm['name'])->value('id');
            if ($id) {
                DB::table('role_permissions')->where('permission_id', $id)->delete();
                DB::table('tenant_permissions')->where('permission_id', $id)->delete();
                DB::table('subscription_plan_permissions')->where('permission_id', $id)->delete();
                DB::table('permissions')->where('id', $id)->delete();
            }
        }
    }
};

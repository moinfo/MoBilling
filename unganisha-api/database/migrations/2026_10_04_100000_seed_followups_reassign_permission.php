<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Reassigning a follow-up takes work away from whoever currently has it — that needs to be
 * an admin-only action. The reassign endpoint was gated behind `documents.approve_collection`,
 * but that permission turned out to already be granted to nearly every role (user, receptionist,
 * accountant, marketing, ...), so any staff member could reassign. This gives reassignment its
 * own permission, seeded admin-only across all three layers (see three-layer permission system).
 */
return new class extends Migration
{
    private array $perms = [
        ['name' => 'followups.reassign', 'label' => 'Reassign a follow-up to another staff member', 'category' => 'crud', 'group_name' => 'Follow-ups'],
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

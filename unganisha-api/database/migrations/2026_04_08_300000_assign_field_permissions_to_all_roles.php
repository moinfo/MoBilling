<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        $fieldPerms = DB::table('permissions')->where('name', 'like', 'field_%')->pluck('id');
        $roles = DB::table('roles')->pluck('id');

        foreach ($roles as $roleId) {
            foreach ($fieldPerms as $permId) {
                DB::table('role_permissions')->insertOrIgnore([
                    'role_id'       => $roleId,
                    'permission_id' => $permId,
                ]);
            }
        }
    }

    public function down(): void
    {
        // intentionally left empty — don't revoke permissions on rollback
    }
};

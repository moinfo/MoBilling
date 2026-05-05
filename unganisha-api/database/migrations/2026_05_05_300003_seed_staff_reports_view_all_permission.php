<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

return new class extends Migration
{
    public function up(): void
    {
        $perm = [
            'name'       => 'staff_reports.view_all',
            'label'      => 'View all staff reports (admin)',
            'category'   => 'crud',
            'group_name' => 'Staff Reports',
        ];

        $existing = DB::table('permissions')->where('name', $perm['name'])->first();
        if ($existing) {
            DB::table('permissions')->where('name', $perm['name'])->update($perm);
            $permId = $existing->id;
        } else {
            $permId = (string) Str::uuid();
            DB::table('permissions')->insert(array_merge(['id' => $permId], $perm));
        }

        // Assign to all existing roles by default (admins can restrict via Roles UI)
        foreach (DB::table('roles')->pluck('id') as $roleId) {
            DB::table('role_permissions')->insertOrIgnore([
                'role_id'       => $roleId,
                'permission_id' => $permId,
            ]);
        }
    }

    public function down(): void {}
};
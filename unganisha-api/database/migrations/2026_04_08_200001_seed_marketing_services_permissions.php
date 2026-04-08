<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

return new class extends Migration
{
    public function up(): void
    {
        $perms = [
            ['name' => 'marketing_services.read',   'label' => 'View Marketing Services'],
            ['name' => 'marketing_services.create',  'label' => 'Create Marketing Services'],
            ['name' => 'marketing_services.update',  'label' => 'Edit Marketing Services'],
            ['name' => 'marketing_services.delete',  'label' => 'Delete Marketing Services'],
        ];

        foreach ($perms as $p) {
            DB::table('permissions')->insertOrIgnore([
                'id'         => (string) Str::uuid(),
                'name'       => $p['name'],
                'label'      => $p['label'],
                'group_name' => 'Marketing Services',
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }
    }

    public function down(): void
    {
        DB::table('permissions')->whereIn('name', [
            'marketing_services.read',
            'marketing_services.create',
            'marketing_services.update',
            'marketing_services.delete',
        ])->delete();
    }
};

<?php

use App\Models\Permission;
use App\Models\Role;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('announcements', function (Blueprint $t) {
            $t->uuid('id')->primary();
            $t->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $t->string('title');
            $t->text('body');
            $t->boolean('is_published')->default(false);
            $t->timestamp('published_at')->nullable();
            $t->foreignUuid('created_by')->nullable()->constrained('users')->nullOnDelete();
            $t->timestamps();
            $t->index(['tenant_id', 'is_published', 'published_at']);
        });

        foreach ([
            ['name' => 'menu.announcements',   'label' => 'Announcements Menu',   'category' => 'menu', 'group_name' => 'Support'],
            ['name' => 'announcements.manage', 'label' => 'Manage Announcements', 'category' => 'crud', 'group_name' => 'Support'],
        ] as $data) {
            Permission::firstOrCreate(['name' => $data['name']], $data);
        }

        $ids = Permission::whereIn('name', ['menu.announcements', 'announcements.manage'])->pluck('id');
        foreach (Role::withoutGlobalScopes()->where('name', 'admin')->get() as $admin) {
            foreach ($ids as $permId) {
                DB::table('role_permissions')->insertOrIgnore([
                    'role_id' => $admin->id, 'permission_id' => $permId,
                ]);
            }
        }
    }

    public function down(): void
    {
        Permission::whereIn('name', ['menu.announcements', 'announcements.manage'])->delete();
        Schema::dropIfExists('announcements');
    }
};

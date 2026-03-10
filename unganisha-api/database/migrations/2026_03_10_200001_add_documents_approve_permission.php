<?php

use App\Models\Permission;
use App\Models\Tenant;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        $permission = Permission::firstOrCreate(
            ['name' => 'documents.approve'],
            ['label' => 'Approve Documents', 'category' => 'crud', 'group_name' => 'Documents']
        );

        // Assign to all existing tenants
        $tenantIds = Tenant::pluck('id');
        $rows = $tenantIds->map(fn ($tenantId) => [
            'tenant_id' => $tenantId,
            'permission_id' => $permission->id,
        ])->toArray();

        DB::table('tenant_permissions')->insertOrIgnore($rows);
    }

    public function down(): void
    {
        Permission::where('name', 'documents.approve')->delete();
    }
};

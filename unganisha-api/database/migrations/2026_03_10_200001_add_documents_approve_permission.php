<?php

use App\Models\Permission;
use Illuminate\Database\Migrations\Migration;

return new class extends Migration
{
    public function up(): void
    {
        Permission::firstOrCreate(
            ['name' => 'documents.approve'],
            ['label' => 'Approve Documents', 'category' => 'crud', 'group_name' => 'Documents']
        );
    }

    public function down(): void
    {
        Permission::where('name', 'documents.approve')->delete();
    }
};

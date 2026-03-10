<?php

use Illuminate\Database\Migrations\Migration;
use App\Models\Permission;

return new class extends Migration
{
    public function up(): void
    {
        Permission::firstOrCreate(
            ['name' => 'expenses.date_range'],
            ['label' => 'Change Expense Date Range', 'category' => 'crud', 'group_name' => 'Expenses']
        );

        Permission::firstOrCreate(
            ['name' => 'client_subscriptions.date_range'],
            ['label' => 'Change Subscription Date Range', 'category' => 'crud', 'group_name' => 'Client Subscriptions']
        );

        Permission::firstOrCreate(
            ['name' => 'documents.date_range'],
            ['label' => 'Change Document Date Range', 'category' => 'crud', 'group_name' => 'Documents']
        );

        Permission::firstOrCreate(
            ['name' => 'payments_in.date_range'],
            ['label' => 'Change Payment Date Range', 'category' => 'crud', 'group_name' => 'Payments In']
        );
    }

    public function down(): void
    {
        Permission::where('name', 'expenses.date_range')->delete();
        Permission::where('name', 'client_subscriptions.date_range')->delete();
        Permission::where('name', 'documents.date_range')->delete();
        Permission::where('name', 'payments_in.date_range')->delete();
    }
};

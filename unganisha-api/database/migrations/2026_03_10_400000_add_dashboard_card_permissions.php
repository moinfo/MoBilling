<?php

use App\Models\Permission;
use App\Models\Role;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    private array $permissions = [
        ['name' => 'dashboard.total_receivable', 'label' => 'View Total Receivable', 'category' => 'dashboard', 'group_name' => 'Dashboard'],
        ['name' => 'dashboard.total_received', 'label' => 'View Total Received', 'category' => 'dashboard', 'group_name' => 'Dashboard'],
        ['name' => 'dashboard.outstanding', 'label' => 'View Outstanding', 'category' => 'dashboard', 'group_name' => 'Dashboard'],
        ['name' => 'dashboard.expenses', 'label' => 'View Expenses', 'category' => 'dashboard', 'group_name' => 'Dashboard'],
        ['name' => 'dashboard.overdue_invoices', 'label' => 'View Overdue Invoices', 'category' => 'dashboard', 'group_name' => 'Dashboard'],
        ['name' => 'dashboard.overdue_bills', 'label' => 'View Overdue Bills', 'category' => 'dashboard', 'group_name' => 'Dashboard'],
        ['name' => 'dashboard.total_clients', 'label' => 'View Total Clients', 'category' => 'dashboard', 'group_name' => 'Dashboard'],
        ['name' => 'dashboard.total_documents', 'label' => 'View Total Documents', 'category' => 'dashboard', 'group_name' => 'Dashboard'],
        ['name' => 'dashboard.overdue_obligations', 'label' => 'View Overdue Obligations', 'category' => 'dashboard', 'group_name' => 'Dashboard'],
        ['name' => 'dashboard.due_soon_obligations', 'label' => 'View Due Soon Obligations', 'category' => 'dashboard', 'group_name' => 'Dashboard'],
        ['name' => 'dashboard.sms_balance', 'label' => 'View SMS Balance', 'category' => 'dashboard', 'group_name' => 'Dashboard'],
        ['name' => 'dashboard.revenue_chart', 'label' => 'View Revenue Chart', 'category' => 'dashboard', 'group_name' => 'Dashboard'],
        ['name' => 'dashboard.invoice_status_chart', 'label' => 'View Invoice Status Chart', 'category' => 'dashboard', 'group_name' => 'Dashboard'],
        ['name' => 'dashboard.payment_method_chart', 'label' => 'View Payment Method Chart', 'category' => 'dashboard', 'group_name' => 'Dashboard'],
        ['name' => 'dashboard.top_clients', 'label' => 'View Top Clients', 'category' => 'dashboard', 'group_name' => 'Dashboard'],
        ['name' => 'dashboard.subscription_stats', 'label' => 'View Subscription Stats', 'category' => 'dashboard', 'group_name' => 'Dashboard'],
        ['name' => 'dashboard.recent_invoices', 'label' => 'View Recent Invoices', 'category' => 'dashboard', 'group_name' => 'Dashboard'],
        ['name' => 'dashboard.upcoming_bills', 'label' => 'View Upcoming Bills', 'category' => 'dashboard', 'group_name' => 'Dashboard'],
        ['name' => 'dashboard.urgent_obligations', 'label' => 'View Urgent Obligations', 'category' => 'dashboard', 'group_name' => 'Dashboard'],
        ['name' => 'dashboard.upcoming_renewals', 'label' => 'View Upcoming Renewals', 'category' => 'dashboard', 'group_name' => 'Dashboard'],
        ['name' => 'dashboard.activity_calendar', 'label' => 'View Activity Calendar', 'category' => 'dashboard', 'group_name' => 'Dashboard'],
    ];

    public function up(): void
    {
        // Add 'dashboard' to the category enum
        DB::statement("ALTER TABLE permissions MODIFY COLUMN category ENUM('menu','crud','settings','reports','dashboard') NOT NULL DEFAULT 'crud'");

        $permIds = [];
        foreach ($this->permissions as $perm) {
            $p = Permission::firstOrCreate(['name' => $perm['name']], $perm);
            $permIds[] = $p->id;
        }

        // Auto-assign all dashboard permissions to existing roles that have menu.dashboard
        $dashboardPerm = Permission::where('name', 'menu.dashboard')->first();
        if ($dashboardPerm) {
            $roles = Role::whereHas('permissions', function ($q) use ($dashboardPerm) {
                $q->where('permissions.id', $dashboardPerm->id);
            })->get();

            foreach ($roles as $role) {
                $role->permissions()->syncWithoutDetaching($permIds);
            }
        }

        // Also assign to tenant_permissions for tenants that have menu.dashboard
        if ($dashboardPerm) {
            $tenantIds = DB::table('tenant_permissions')
                ->where('permission_id', $dashboardPerm->id)
                ->pluck('tenant_id');

            $inserts = [];
            foreach ($tenantIds as $tenantId) {
                foreach ($permIds as $permId) {
                    $inserts[] = ['tenant_id' => $tenantId, 'permission_id' => $permId];
                }
            }

            if (!empty($inserts)) {
                DB::table('tenant_permissions')->insertOrIgnore($inserts);
            }
        }
    }

    public function down(): void
    {
        $names = array_column($this->permissions, 'name');
        Permission::whereIn('name', $names)->delete();

        DB::statement("ALTER TABLE permissions MODIFY COLUMN category ENUM('menu','crud','settings','reports') NOT NULL DEFAULT 'crud'");
    }
};

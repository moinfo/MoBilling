<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

return new class extends Migration
{
    public function up(): void
    {
        // 1. Seed all 78 permissions
        $permissions = $this->getPermissions();
        $permissionRows = [];
        $permissionMap = []; // name => id

        foreach ($permissions as $perm) {
            $id = Str::uuid()->toString();
            $permissionMap[$perm['name']] = $id;
            $permissionRows[] = [
                'id' => $id,
                'name' => $perm['name'],
                'label' => $perm['label'],
                'category' => $perm['category'],
                'group_name' => $perm['group_name'],
                'created_at' => now(),
                'updated_at' => now(),
            ];
        }

        DB::table('permissions')->insert($permissionRows);

        // 2. Get all tenants
        $tenants = DB::table('tenants')->get();

        foreach ($tenants as $tenant) {
            // 3. Grant ALL permissions to each tenant
            $tenantPermRows = [];
            foreach ($permissionMap as $permId) {
                $tenantPermRows[] = [
                    'tenant_id' => $tenant->id,
                    'permission_id' => $permId,
                ];
            }
            DB::table('tenant_permissions')->insert($tenantPermRows);

            // 4. Create admin role
            $adminRoleId = Str::uuid()->toString();
            DB::table('roles')->insert([
                'id' => $adminRoleId,
                'tenant_id' => $tenant->id,
                'name' => 'admin',
                'label' => 'Administrator',
                'is_system' => true,
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            // Admin gets ALL permissions
            $adminPerms = [];
            foreach ($permissionMap as $permId) {
                $adminPerms[] = [
                    'role_id' => $adminRoleId,
                    'permission_id' => $permId,
                ];
            }
            DB::table('role_permissions')->insert($adminPerms);

            // 5. Create user role
            $userRoleId = Str::uuid()->toString();
            DB::table('roles')->insert([
                'id' => $userRoleId,
                'tenant_id' => $tenant->id,
                'name' => 'user',
                'label' => 'User',
                'is_system' => true,
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            // User gets limited permissions
            $userPermNames = $this->getUserPermissionNames();
            $userPerms = [];
            foreach ($userPermNames as $permName) {
                if (isset($permissionMap[$permName])) {
                    $userPerms[] = [
                        'role_id' => $userRoleId,
                        'permission_id' => $permissionMap[$permName],
                    ];
                }
            }
            DB::table('role_permissions')->insert($userPerms);

            // 6. Map existing users to new role_id
            DB::table('users')
                ->where('tenant_id', $tenant->id)
                ->where('role', 'admin')
                ->update(['role_id' => $adminRoleId]);

            DB::table('users')
                ->where('tenant_id', $tenant->id)
                ->where('role', 'user')
                ->update(['role_id' => $userRoleId]);
        }
    }

    public function down(): void
    {
        // Clear role_id from all users
        DB::table('users')->update(['role_id' => null]);

        // Remove all seeded data (cascade will handle pivots)
        DB::table('roles')->delete();
        DB::table('permissions')->delete();
        DB::table('tenant_permissions')->delete();
        DB::table('role_permissions')->delete();
    }

    private function getPermissions(): array
    {
        return [
            // MENU permissions (21)
            ['name' => 'menu.dashboard', 'label' => 'Dashboard', 'category' => 'menu', 'group_name' => 'Navigation'],
            ['name' => 'menu.clients', 'label' => 'Clients', 'category' => 'menu', 'group_name' => 'Navigation'],
            ['name' => 'menu.products', 'label' => 'Products & Services', 'category' => 'menu', 'group_name' => 'Navigation'],
            ['name' => 'menu.quotations', 'label' => 'Quotations', 'category' => 'menu', 'group_name' => 'Billing'],
            ['name' => 'menu.proformas', 'label' => 'Proforma Invoices', 'category' => 'menu', 'group_name' => 'Billing'],
            ['name' => 'menu.invoices', 'label' => 'Invoices', 'category' => 'menu', 'group_name' => 'Billing'],
            ['name' => 'menu.payments_in', 'label' => 'Payments Received', 'category' => 'menu', 'group_name' => 'Billing'],
            ['name' => 'menu.client_subscriptions', 'label' => 'Client Subscriptions', 'category' => 'menu', 'group_name' => 'Billing'],
            ['name' => 'menu.next_bills', 'label' => 'Next Bills', 'category' => 'menu', 'group_name' => 'Billing'],
            ['name' => 'menu.collection', 'label' => 'Collection', 'category' => 'menu', 'group_name' => 'Navigation'],
            ['name' => 'menu.followups', 'label' => 'Follow-ups', 'category' => 'menu', 'group_name' => 'Navigation'],
            ['name' => 'menu.statutories', 'label' => 'Statutory Obligations', 'category' => 'menu', 'group_name' => 'Statutory'],
            ['name' => 'menu.statutory_bills', 'label' => 'Statutory Bills', 'category' => 'menu', 'group_name' => 'Statutory'],
            ['name' => 'menu.bill_categories', 'label' => 'Bill Categories', 'category' => 'menu', 'group_name' => 'Statutory'],
            ['name' => 'menu.payments_out', 'label' => 'Payment History', 'category' => 'menu', 'group_name' => 'Statutory'],
            ['name' => 'menu.expense_categories', 'label' => 'Expense Categories', 'category' => 'menu', 'group_name' => 'Expenses'],
            ['name' => 'menu.expenses', 'label' => 'Expenses', 'category' => 'menu', 'group_name' => 'Expenses'],
            ['name' => 'menu.automation', 'label' => 'Automation', 'category' => 'menu', 'group_name' => 'Navigation'],
            ['name' => 'menu.reports', 'label' => 'Reports', 'category' => 'menu', 'group_name' => 'Navigation'],
            ['name' => 'menu.sms', 'label' => 'SMS', 'category' => 'menu', 'group_name' => 'Navigation'],
            ['name' => 'menu.users', 'label' => 'Team / Users', 'category' => 'menu', 'group_name' => 'Navigation'],

            // CRUD permissions (44)
            ['name' => 'clients.create', 'label' => 'Create Clients', 'category' => 'crud', 'group_name' => 'Clients'],
            ['name' => 'clients.read', 'label' => 'View Clients', 'category' => 'crud', 'group_name' => 'Clients'],
            ['name' => 'clients.update', 'label' => 'Edit Clients', 'category' => 'crud', 'group_name' => 'Clients'],
            ['name' => 'clients.delete', 'label' => 'Delete Clients', 'category' => 'crud', 'group_name' => 'Clients'],

            ['name' => 'products.create', 'label' => 'Create Products', 'category' => 'crud', 'group_name' => 'Products'],
            ['name' => 'products.read', 'label' => 'View Products', 'category' => 'crud', 'group_name' => 'Products'],
            ['name' => 'products.update', 'label' => 'Edit Products', 'category' => 'crud', 'group_name' => 'Products'],
            ['name' => 'products.delete', 'label' => 'Delete Products', 'category' => 'crud', 'group_name' => 'Products'],

            ['name' => 'documents.create', 'label' => 'Create Documents', 'category' => 'crud', 'group_name' => 'Documents'],
            ['name' => 'documents.read', 'label' => 'View Documents', 'category' => 'crud', 'group_name' => 'Documents'],
            ['name' => 'documents.update', 'label' => 'Edit Documents', 'category' => 'crud', 'group_name' => 'Documents'],
            ['name' => 'documents.delete', 'label' => 'Delete Documents', 'category' => 'crud', 'group_name' => 'Documents'],
            ['name' => 'documents.send', 'label' => 'Send Documents', 'category' => 'crud', 'group_name' => 'Documents'],
            ['name' => 'documents.convert', 'label' => 'Convert Documents', 'category' => 'crud', 'group_name' => 'Documents'],
            ['name' => 'documents.download', 'label' => 'Download Documents', 'category' => 'crud', 'group_name' => 'Documents'],

            ['name' => 'payments_in.create', 'label' => 'Record Payments', 'category' => 'crud', 'group_name' => 'Payments In'],
            ['name' => 'payments_in.read', 'label' => 'View Payments', 'category' => 'crud', 'group_name' => 'Payments In'],
            ['name' => 'payments_in.update', 'label' => 'Edit Payments', 'category' => 'crud', 'group_name' => 'Payments In'],
            ['name' => 'payments_in.delete', 'label' => 'Delete Payments', 'category' => 'crud', 'group_name' => 'Payments In'],
            ['name' => 'payments_in.resend_receipt', 'label' => 'Resend Receipt', 'category' => 'crud', 'group_name' => 'Payments In'],

            ['name' => 'client_subscriptions.create', 'label' => 'Create Subscriptions', 'category' => 'crud', 'group_name' => 'Client Subscriptions'],
            ['name' => 'client_subscriptions.read', 'label' => 'View Subscriptions', 'category' => 'crud', 'group_name' => 'Client Subscriptions'],
            ['name' => 'client_subscriptions.update', 'label' => 'Edit Subscriptions', 'category' => 'crud', 'group_name' => 'Client Subscriptions'],
            ['name' => 'client_subscriptions.delete', 'label' => 'Delete Subscriptions', 'category' => 'crud', 'group_name' => 'Client Subscriptions'],

            ['name' => 'statutories.create', 'label' => 'Create Statutory', 'category' => 'crud', 'group_name' => 'Statutories'],
            ['name' => 'statutories.read', 'label' => 'View Statutory', 'category' => 'crud', 'group_name' => 'Statutories'],
            ['name' => 'statutories.update', 'label' => 'Edit Statutory', 'category' => 'crud', 'group_name' => 'Statutories'],
            ['name' => 'statutories.delete', 'label' => 'Delete Statutory', 'category' => 'crud', 'group_name' => 'Statutories'],

            ['name' => 'bills.create', 'label' => 'Create Bills', 'category' => 'crud', 'group_name' => 'Bills'],
            ['name' => 'bills.read', 'label' => 'View Bills', 'category' => 'crud', 'group_name' => 'Bills'],
            ['name' => 'bills.update', 'label' => 'Edit Bills', 'category' => 'crud', 'group_name' => 'Bills'],
            ['name' => 'bills.delete', 'label' => 'Delete Bills', 'category' => 'crud', 'group_name' => 'Bills'],

            ['name' => 'payments_out.create', 'label' => 'Record Bill Payments', 'category' => 'crud', 'group_name' => 'Payments Out'],
            ['name' => 'payments_out.read', 'label' => 'View Bill Payments', 'category' => 'crud', 'group_name' => 'Payments Out'],
            ['name' => 'payments_out.update', 'label' => 'Edit Bill Payments', 'category' => 'crud', 'group_name' => 'Payments Out'],
            ['name' => 'payments_out.delete', 'label' => 'Delete Bill Payments', 'category' => 'crud', 'group_name' => 'Payments Out'],

            ['name' => 'expense_categories.create', 'label' => 'Create Expense Categories', 'category' => 'crud', 'group_name' => 'Expense Categories'],
            ['name' => 'expense_categories.read', 'label' => 'View Expense Categories', 'category' => 'crud', 'group_name' => 'Expense Categories'],
            ['name' => 'expense_categories.update', 'label' => 'Edit Expense Categories', 'category' => 'crud', 'group_name' => 'Expense Categories'],
            ['name' => 'expense_categories.delete', 'label' => 'Delete Expense Categories', 'category' => 'crud', 'group_name' => 'Expense Categories'],

            ['name' => 'expenses.create', 'label' => 'Create Expenses', 'category' => 'crud', 'group_name' => 'Expenses'],
            ['name' => 'expenses.read', 'label' => 'View Expenses', 'category' => 'crud', 'group_name' => 'Expenses'],
            ['name' => 'expenses.update', 'label' => 'Edit Expenses', 'category' => 'crud', 'group_name' => 'Expenses'],
            ['name' => 'expenses.delete', 'label' => 'Delete Expenses', 'category' => 'crud', 'group_name' => 'Expenses'],

            // SETTINGS permissions (7)
            ['name' => 'settings.company', 'label' => 'Company Settings', 'category' => 'settings', 'group_name' => 'Settings'],
            ['name' => 'settings.reminders', 'label' => 'Reminder Settings', 'category' => 'settings', 'group_name' => 'Settings'],
            ['name' => 'settings.templates', 'label' => 'Template Settings', 'category' => 'settings', 'group_name' => 'Settings'],
            ['name' => 'settings.payment_methods', 'label' => 'Payment Methods', 'category' => 'settings', 'group_name' => 'Settings'],
            ['name' => 'settings.email', 'label' => 'Email Settings', 'category' => 'settings', 'group_name' => 'Settings'],
            ['name' => 'settings.profile', 'label' => 'My Profile', 'category' => 'settings', 'group_name' => 'Settings'],
            ['name' => 'settings.users', 'label' => 'Manage Users & Roles', 'category' => 'settings', 'group_name' => 'Settings'],

            // REPORTS permissions (10)
            ['name' => 'reports.revenue', 'label' => 'Revenue Report', 'category' => 'reports', 'group_name' => 'Reports'],
            ['name' => 'reports.aging', 'label' => 'Aging Report', 'category' => 'reports', 'group_name' => 'Reports'],
            ['name' => 'reports.client_statement', 'label' => 'Client Statement', 'category' => 'reports', 'group_name' => 'Reports'],
            ['name' => 'reports.payment_collection', 'label' => 'Payment Collection', 'category' => 'reports', 'group_name' => 'Reports'],
            ['name' => 'reports.expense', 'label' => 'Expense Report', 'category' => 'reports', 'group_name' => 'Reports'],
            ['name' => 'reports.profit_loss', 'label' => 'Profit & Loss', 'category' => 'reports', 'group_name' => 'Reports'],
            ['name' => 'reports.statutory', 'label' => 'Statutory Report', 'category' => 'reports', 'group_name' => 'Reports'],
            ['name' => 'reports.subscription', 'label' => 'Subscription Report', 'category' => 'reports', 'group_name' => 'Reports'],
            ['name' => 'reports.collection', 'label' => 'Collection Report', 'category' => 'reports', 'group_name' => 'Reports'],
            ['name' => 'reports.communication', 'label' => 'Communication Log', 'category' => 'reports', 'group_name' => 'Reports'],
        ];
    }

    private function getUserPermissionNames(): array
    {
        return [
            // All menu permissions
            'menu.dashboard', 'menu.clients', 'menu.products',
            'menu.quotations', 'menu.proformas', 'menu.invoices',
            'menu.payments_in', 'menu.client_subscriptions', 'menu.next_bills',
            'menu.collection', 'menu.followups',
            'menu.statutories', 'menu.statutory_bills', 'menu.bill_categories', 'menu.payments_out',
            'menu.expense_categories', 'menu.expenses',
            'menu.automation', 'menu.reports', 'menu.sms',

            // Read all
            'clients.read', 'products.read', 'documents.read',
            'payments_in.read', 'client_subscriptions.read',
            'statutories.read', 'bills.read', 'payments_out.read',
            'expense_categories.read', 'expenses.read',

            // Create/update documents, payments, expenses
            'documents.create', 'documents.update', 'documents.send', 'documents.download',
            'payments_in.create', 'payments_in.update',
            'expenses.create', 'expenses.update',

            // Profile settings
            'settings.profile',

            // All reports
            'reports.revenue', 'reports.aging', 'reports.client_statement',
            'reports.payment_collection', 'reports.expense', 'reports.profit_loss',
            'reports.statutory', 'reports.subscription', 'reports.collection',
            'reports.communication',
        ];
    }
};

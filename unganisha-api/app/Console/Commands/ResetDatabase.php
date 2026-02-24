<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

class ResetDatabase extends Command
{
    protected $signature = 'db:reset-data {--force : Skip confirmation prompt}';

    protected $description = 'Clear all data except the super admin user and platform config (plans, currencies, SMS packages)';

    public function handle(): int
    {
        if (!$this->option('force') && !$this->confirm('This will DELETE all tenants, clients, documents, bills, expenses, and payments. Continue?')) {
            $this->info('Aborted.');
            return self::SUCCESS;
        }

        DB::statement('SET FOREIGN_KEY_CHECKS=0');

        // Tenant data tables (order doesn't matter with FK checks off)
        $tables = [
            'recurring_invoice_logs',
            'payments_in',
            'document_items',
            'documents',
            'payments_out',
            'bills',
            'statutories',
            'bill_categories',
            'expenses',
            'sub_expense_categories',
            'expense_categories',
            'client_subscriptions',
            'product_services',
            'clients',
            'tenant_subscriptions',
            'sms_purchases',
            'notifications',
            'personal_access_tokens',
        ];

        foreach ($tables as $table) {
            DB::table($table)->truncate();
            $this->line("  Truncated <comment>{$table}</comment>");
        }

        // Delete all non-super-admin users
        $kept = DB::table('users')->where('role', 'super_admin')->count();
        DB::table('users')->where('role', '!=', 'super_admin')->delete();
        $this->line("  Cleaned <comment>users</comment> (kept {$kept} super admin(s))");

        // Delete all tenants
        DB::table('tenants')->truncate();
        $this->line("  Truncated <comment>tenants</comment>");

        // Clear super admin's tenant_id since tenants are gone
        DB::table('users')->where('role', 'super_admin')->update(['tenant_id' => null]);

        // Clear cache and sessions
        foreach (['cache', 'cache_locks', 'sessions', 'jobs', 'failed_jobs', 'job_batches'] as $table) {
            DB::table($table)->truncate();
        }
        $this->line("  Cleared cache, sessions, and jobs");

        DB::statement('SET FOREIGN_KEY_CHECKS=1');

        $this->newLine();
        $this->info('Database reset complete. Preserved: super admin, subscription plans, currencies, SMS packages, platform settings.');

        return self::SUCCESS;
    }
}

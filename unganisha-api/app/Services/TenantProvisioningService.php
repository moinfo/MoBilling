<?php

namespace App\Services;

use App\Models\Permission;
use App\Models\Role;
use App\Models\Tenant;
use App\Models\User;

/**
 * Turns {tenant fields} + {admin user fields} into a fully provisioned
 * tenant: allowedPermissions ceiling, `admin`/`user` system Roles, and the
 * first admin User. Shared by Auth\RegisterController::register() (public
 * self-signup) and Admin\TenantController::promoteFromClient() (super-admin
 * "promote an existing client into their own tenant") — both used to carry
 * a byte-for-byte copy of this logic, which is exactly the kind of thing
 * that quietly drifts out of sync when only one of the two gets updated.
 *
 * `$tier` selects the product being sold:
 *  - 'general'  — every permission in the system (unchanged from the
 *                 original behavior both callers had before this existed).
 *  - 'reseller' — "Domain & Hosting Reseller" — a curated WHMCS-parity
 *                 subset (clients/products/documents/payments/domains/
 *                 hosting/tickets/etc.), deliberately excluding the Kenya/
 *                 Tanzania statutory-compliance vertical (statutories,
 *                 bills, payments_out, expenses) and the separate CRM/
 *                 field-ops vertical (WhatsApp, social, field marketing,
 *                 satisfaction calls, served customers, system records/
 *                 verifications/properties, staff reports/targets, petty
 *                 cash, attendance, announcements) that a hosting-reseller
 *                 customer has no use for.
 */
class TenantProvisioningService
{
    private const RESELLER_PERMISSIONS = [
        // menu
        'menu.client_subscriptions', 'menu.clients', 'menu.invoices', 'menu.next_bills',
        'menu.payments_in', 'menu.products', 'menu.proformas', 'menu.quotations',
        'menu.domains', 'menu.hosting',
        'menu.bank_accounts', 'menu.collection', 'menu.dashboard', 'menu.followups',
        'menu.automation', 'menu.reports', 'menu.roles', 'menu.settings', 'menu.sms',
        'menu.subscription', 'menu.users', 'menu.tickets',

        // bank accounts
        'bank_accounts.create', 'bank_accounts.delete', 'bank_accounts.read', 'bank_accounts.update',
        // wallet / ordering
        'credit.manage', 'orders.create',
        // client profile
        'client_profile.active_subscriptions', 'client_profile.balance_due',
        'client_profile.subscription_price', 'client_profile.subscription_value',
        'client_profile.total_invoiced', 'client_profile.total_paid',
        // client subscriptions
        'client_subscriptions.create', 'client_subscriptions.date_range', 'client_subscriptions.delete',
        'client_subscriptions.read', 'client_subscriptions.renew', 'client_subscriptions.update',
        // clients
        'clients.create', 'clients.delete', 'clients.portal_login', 'clients.portal_password',
        'clients.read', 'clients.update',
        // documents (invoices/quotations/proformas)
        'documents.approve', 'documents.convert', 'documents.create', 'documents.date_range',
        'documents.delete', 'documents.download', 'documents.extend_due_date', 'documents.read',
        'documents.send', 'documents.update',
        // domains
        'domains.create', 'domains.manage_dns', 'domains.read', 'domains.renew',
        'domains.settings', 'domains.transfer',
        // hosting
        'hosting.change_package', 'hosting.create', 'hosting.read', 'hosting.settings',
        'hosting.sso', 'hosting.suspend', 'hosting.terminate',
        // payments in
        'payments_in.create', 'payments_in.date_range', 'payments_in.delete', 'payments_in.read',
        'payments_in.resend_receipt', 'payments_in.update',
        // products
        'products.create', 'products.delete', 'products.read', 'products.update',
        // support tickets
        'tickets.manage', 'tickets.read', 'tickets.reply',

        // settings
        'settings.company', 'settings.email', 'settings.payment_methods', 'settings.profile',
        'settings.reminders', 'settings.templates', 'settings.users',

        // reports
        'reports.aging', 'reports.client_statement', 'reports.collection', 'reports.communication',
        'reports.payment_collection', 'reports.revenue', 'reports.subscription',

        // dashboard
        'dashboard.activity_calendar', 'dashboard.bank_account_breakdown', 'dashboard.domains',
        'dashboard.hosting', 'dashboard.invoice_status_chart', 'dashboard.month_filter',
        'dashboard.outstanding', 'dashboard.overdue_invoices', 'dashboard.payment_method_chart',
        'dashboard.recent_invoices', 'dashboard.revenue_chart', 'dashboard.sms_balance',
        'dashboard.subscription_stats', 'dashboard.tickets', 'dashboard.top_clients',
        'dashboard.total_clients', 'dashboard.total_documents', 'dashboard.total_receivable',
        'dashboard.total_received', 'dashboard.upcoming_renewals',
    ];

    /** The existing "user" (restricted staff) role whitelist — unchanged from
     *  the original RegisterController::register()/promoteFromClient() copy. */
    private const USER_PERMISSIONS = [
        'menu.dashboard',
        'dashboard.total_receivable', 'dashboard.total_received', 'dashboard.outstanding',
        'dashboard.expenses', 'dashboard.overdue_invoices', 'dashboard.overdue_bills',
        'dashboard.total_clients', 'dashboard.total_documents',
        'dashboard.overdue_obligations', 'dashboard.due_soon_obligations', 'dashboard.sms_balance',
        'dashboard.revenue_chart', 'dashboard.invoice_status_chart', 'dashboard.payment_method_chart',
        'dashboard.top_clients', 'dashboard.subscription_stats',
        'dashboard.recent_invoices', 'dashboard.upcoming_bills',
        'dashboard.urgent_obligations', 'dashboard.upcoming_renewals', 'dashboard.activity_calendar',
        'menu.clients', 'menu.products',
        'menu.quotations', 'menu.proformas', 'menu.invoices',
        'menu.payments_in', 'menu.client_subscriptions', 'menu.next_bills',
        'menu.collection', 'menu.followups',
        'menu.statutories', 'menu.statutory_bills', 'menu.bill_categories', 'menu.payments_out',
        'menu.expense_categories', 'menu.expenses',
        'menu.automation', 'menu.reports', 'menu.sms',
        'menu.satisfaction_calls',
        'menu.employees', 'menu.leave', 'leave.submit',
        'client_profile.total_invoiced', 'client_profile.total_paid', 'client_profile.balance_due',
        'client_profile.active_subscriptions', 'client_profile.subscription_value', 'client_profile.subscription_price',
        'clients.read', 'products.read', 'documents.read',
        'payments_in.read', 'client_subscriptions.read',
        'statutories.read', 'bills.read', 'payments_out.read',
        'expense_categories.read', 'expenses.read',
        'documents.create', 'documents.update', 'documents.send', 'documents.download', 'documents.approve',
        'payments_in.create', 'payments_in.update',
        'expenses.create', 'expenses.update',
        'settings.profile',
        'reports.revenue', 'reports.aging', 'reports.client_statement',
        'reports.payment_collection', 'reports.expense', 'reports.profit_loss',
        'reports.statutory', 'reports.subscription', 'reports.collection',
        'reports.satisfaction', 'reports.communication',
    ];

    /**
     * @param array $tenantData Tenant::create() fields (name, email, phone, address, tax_id, currency, trial_ends_at, ...)
     * @param array $adminData  User::create() fields for the first admin (name, email, password, phone?)
     * @param ?callable $afterTenantCreated Called with the new Tenant right after it's created, before any
     *   Role/User writes — lets an authenticated caller (e.g. a super admin promoting a client) patch its
     *   own in-memory tenant_id so BelongsToTenant's creating() hook stamps the new tenant's id instead of
     *   the caller's (null for a super admin). Unnecessary for unauthenticated callers like self-signup.
     * @return array{0: Tenant, 1: User} [$tenant, $adminUser]
     */
    public function provision(array $tenantData, array $adminData, string $tier = 'general', ?callable $afterTenantCreated = null): array
    {
        $tenant = Tenant::create($tenantData);
        if ($afterTenantCreated) {
            $afterTenantCreated($tenant);
        }

        $allPermissionIds = Permission::pluck('id');
        $ceilingIds = $tier === 'reseller'
            ? Permission::whereIn('name', self::RESELLER_PERMISSIONS)->pluck('id')
            : $allPermissionIds;

        $tenant->allowedPermissions()->sync($ceilingIds);

        $adminRole = Role::create(['tenant_id' => $tenant->id, 'name' => 'admin', 'label' => 'Administrator', 'is_system' => true]);
        $adminRole->permissions()->sync($ceilingIds);

        $userRole = Role::create(['tenant_id' => $tenant->id, 'name' => 'user', 'label' => 'User', 'is_system' => true]);
        $userIds = Permission::whereIn('name', self::USER_PERMISSIONS)->pluck('id')->intersect($ceilingIds);
        $userRole->permissions()->sync($userIds);

        $adminUser = User::create([
            ...$adminData,
            'tenant_id' => $tenant->id,
            'role' => 'admin',
            'role_id' => $adminRole->id,
        ]);

        return [$tenant, $adminUser];
    }
}

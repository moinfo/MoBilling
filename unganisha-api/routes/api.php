<?php

use App\Http\Controllers\Admin\AdminUserController;
use App\Http\Controllers\Admin\CurrencyController;
use App\Http\Controllers\Admin\DashboardController as AdminDashboardController;
use App\Http\Controllers\Admin\EmailSettingsController as AdminEmailSettingsController;
use App\Http\Controllers\Admin\SmsPackageController;
use App\Http\Controllers\Admin\SmsPurchaseController as AdminSmsPurchaseController;
use App\Http\Controllers\Admin\SmsSettingsController;
use App\Http\Controllers\Admin\PlatformSettingsController;
use App\Http\Controllers\Admin\SubscriptionPlanController;
use App\Http\Controllers\Admin\TemplatesController as AdminTemplatesController;
use App\Http\Controllers\Admin\TenantController;
use App\Http\Controllers\Admin\RoleTemplateController;
use App\Http\Controllers\Admin\TenantPermissionController;
use App\Http\Controllers\Admin\TenantSubscriptionController;
use App\Http\Controllers\RoleController;
use App\Http\Controllers\ClientPortalUserController;
use App\Http\Controllers\BroadcastController;
use App\Http\Controllers\Portal\PortalAuthController;
use App\Http\Controllers\Portal\PortalDashboardController;
use App\Http\Controllers\Portal\PortalDocumentController;
use App\Http\Controllers\Portal\PortalPaymentController;
use App\Http\Controllers\Portal\PortalProfileController;
use App\Http\Controllers\Portal\PortalStatementController;
use App\Http\Controllers\Portal\PortalProductServiceController;
use App\Http\Controllers\Portal\PortalSubscriptionController;
use App\Http\Controllers\EmailSettingsController;
use App\Http\Controllers\ReportController;
use App\Http\Controllers\ExpenseCategoryController;
use App\Http\Controllers\PettyCashController;
use App\Http\Controllers\ExpenseController;
use App\Http\Controllers\SystemController;
use App\Http\Controllers\BankAccountController;
use App\Http\Controllers\SystemPropertyController;
use App\Http\Controllers\SystemRecordController;
use App\Http\Controllers\SystemVerificationController;
use App\Http\Controllers\NotificationController;
use App\Http\Controllers\AutomationController;
use App\Http\Controllers\CollectionController;
use App\Http\Controllers\FollowupController;
use App\Http\Controllers\SatisfactionCallController;
use App\Http\Controllers\Auth\LoginController;
use App\Http\Controllers\Auth\PasswordResetController;
use App\Http\Controllers\Auth\RegisterController;
use App\Http\Controllers\BillCategoryController;
use App\Http\Controllers\BillController;
use App\Http\Controllers\ClientController;
use App\Http\Controllers\ClientSubscriptionController;
use App\Http\Controllers\DashboardController;
use App\Http\Controllers\DocumentController;
use App\Http\Controllers\NextBillController;
use App\Http\Controllers\PaymentInController;
use App\Http\Controllers\PaymentOutController;
use App\Http\Controllers\InvoicePaymentController;
use App\Http\Controllers\PesapalWebhookController;
use App\Http\Controllers\TenantPesapalWebhookController;
use App\Http\Controllers\ProductServiceController;
use App\Http\Controllers\SettingsController;
use App\Http\Controllers\SmsPurchaseController;
use App\Http\Controllers\StatutoryController;
use App\Http\Controllers\SubscriptionController;
use App\Http\Controllers\UserController;
use Illuminate\Support\Facades\Route;

// Public
Route::get('/plans', [SubscriptionController::class, 'plans']);

// Auth (Public)
Route::post('/auth/register', [RegisterController::class, 'register']);
Route::post('/auth/login', [LoginController::class, 'login']);
Route::post('/auth/forgot-password', [PasswordResetController::class, 'forgotPassword']);
Route::post('/auth/verify-reset-otp', [PasswordResetController::class, 'verifyOtp']);
Route::post('/auth/reset-password', [PasswordResetController::class, 'resetPassword']);

// Portal self-registration (public)
Route::post('/portal/request-otp', [PortalAuthController::class, 'requestOtp']);
Route::post('/portal/verify-register', [PortalAuthController::class, 'verifyAndRegister']);

// Pesapal webhooks (public, no auth)
Route::match(['get', 'post'], '/pesapal/ipn', [PesapalWebhookController::class, 'ipn']);
Route::get('/pesapal/callback', [PesapalWebhookController::class, 'callback']);

// Tenant Pesapal webhooks (public, no auth)
Route::match(['get', 'post'], '/tenant-pesapal/ipn', [TenantPesapalWebhookController::class, 'ipn']);

// Public invoice payment (no auth required)
Route::get('/pay/{document}', [InvoicePaymentController::class, 'show']);
Route::post('/pay/{document}/checkout', [InvoicePaymentController::class, 'checkout']);
Route::get('/pay/{document}/status/{payment}', [InvoicePaymentController::class, 'status']);
Route::get('/pay/status/by-tracking', [InvoicePaymentController::class, 'statusByTracking']);

// Auth (Authenticated, no tenant required)
Route::middleware(['auth:sanctum'])->group(function () {
    Route::post('/auth/logout', [LoginController::class, 'logout']);
    Route::get('/auth/me', [LoginController::class, 'me']);

    // Notifications (available to all authenticated users — tenant + admin)
    Route::get('/notifications', [NotificationController::class, 'index']);
    Route::get('/notifications/unread-count', [NotificationController::class, 'unreadCount']);
    Route::patch('/notifications/{id}/read', [NotificationController::class, 'markAsRead']);
    Route::post('/notifications/mark-all-read', [NotificationController::class, 'markAllAsRead']);

    // Active currencies (for dropdowns — available to all authenticated users)
    Route::get('/currencies', [CurrencyController::class, 'active']);

    // Subscription (no tenant middleware — expired tenants must access)
    Route::get('/subscription/plans', [SubscriptionController::class, 'plans']);
    Route::get('/subscription/current', [SubscriptionController::class, 'current']);
    Route::post('/subscription/checkout', [SubscriptionController::class, 'checkout']);
    Route::get('/subscription/history', [SubscriptionController::class, 'history']);
    Route::get('/subscription/{tenantSubscription}/status', [SubscriptionController::class, 'status']);
    Route::get('/subscription/{tenantSubscription}/invoice', [SubscriptionController::class, 'downloadInvoice']);
    Route::post('/subscription/{tenantSubscription}/proof', [SubscriptionController::class, 'uploadProof']);
});

// Super Admin routes (no tenant middleware)
Route::middleware(['auth:sanctum'])->prefix('admin')->group(function () {
    Route::get('/dashboard', [AdminDashboardController::class, 'summary']);
    Route::apiResource('tenants', TenantController::class)->except(['destroy']);
    Route::patch('/tenants/{tenant}/toggle-active', [TenantController::class, 'toggleActive']);

    // Tenant user management
    Route::get('/tenants/{tenant}/users', [AdminUserController::class, 'index']);
    Route::post('/tenants/{tenant}/users', [AdminUserController::class, 'store']);
    Route::put('/tenants/{tenant}/users/{user}', [AdminUserController::class, 'update']);
    Route::patch('/tenants/{tenant}/users/{user}/toggle-active', [AdminUserController::class, 'toggleActive']);

    // Tenant email settings (super admin)
    Route::get('/tenants/{tenant}/email-settings', [AdminEmailSettingsController::class, 'show']);
    Route::put('/tenants/{tenant}/email-settings', [AdminEmailSettingsController::class, 'update']);
    Route::post('/tenants/{tenant}/email-settings/test', [AdminEmailSettingsController::class, 'test']);

    // Tenant email templates (super admin)
    Route::get('/tenants/{tenant}/templates', [AdminTemplatesController::class, 'show']);
    Route::put('/tenants/{tenant}/templates', [AdminTemplatesController::class, 'update']);

    // Impersonate tenant (as admin) or specific user
    Route::post('/tenants/{tenant}/impersonate', [TenantController::class, 'impersonate']);
    Route::post('/tenants/{tenant}/users/{user}/impersonate', [TenantController::class, 'impersonateUser']);

    // Tenant SMS settings (super admin)
    Route::get('/tenants/{tenant}/sms-settings', [SmsSettingsController::class, 'show']);
    Route::put('/tenants/{tenant}/sms-settings', [SmsSettingsController::class, 'update']);
    Route::post('/tenants/{tenant}/sms-recharge', [SmsSettingsController::class, 'recharge']);
    Route::post('/tenants/{tenant}/sms-deduct', [SmsSettingsController::class, 'deduct']);

    // SMS packages (super admin)
    Route::apiResource('sms-packages', SmsPackageController::class)->except(['show']);

    // SMS purchases (super admin view)
    Route::get('/sms-purchases', [AdminSmsPurchaseController::class, 'index']);

    // Currencies (super admin CRUD)
    Route::apiResource('currencies', CurrencyController::class)->except(['show']);

    // Subscription plans (super admin)
    Route::apiResource('subscription-plans', SubscriptionPlanController::class)->except(['show']);

    // Tenant subscriptions (super admin)
    Route::get('/tenants/{tenant}/subscriptions', [TenantSubscriptionController::class, 'index']);
    Route::post('/tenants/{tenant}/subscriptions/extend', [TenantSubscriptionController::class, 'extend']);

    // Confirm bank transfer payment (super admin)
    Route::post('/subscriptions/{tenantSubscription}/confirm-payment', [TenantController::class, 'confirmSubscriptionPayment']);

    // Platform settings (super admin)
    Route::get('/platform-settings', [PlatformSettingsController::class, 'index']);
    Route::put('/platform-settings', [PlatformSettingsController::class, 'update']);

    // Role templates (super admin)
    Route::get('/role-templates', [RoleTemplateController::class, 'index']);
    Route::get('/role-templates/{type}', [RoleTemplateController::class, 'show']);
    Route::put('/role-templates/{type}', [RoleTemplateController::class, 'update']);

    // Permissions management (super admin)
    Route::get('/permissions', [TenantPermissionController::class, 'allPermissions']);
    Route::get('/permissions/{permission}/tenants', [TenantPermissionController::class, 'permissionTenants']);
    Route::put('/permissions/{permission}/tenants', [TenantPermissionController::class, 'updatePermissionTenants']);
    Route::get('/tenants/{tenant}/permissions', [TenantPermissionController::class, 'tenantPermissions']);
    Route::put('/tenants/{tenant}/permissions', [TenantPermissionController::class, 'updateTenantPermissions']);
});

// Tenant-scoped routes
Route::middleware(['auth:sanctum', 'tenant'])->group(function () {

    // Clients
    Route::middleware('permission:clients.read')->get('/clients', [ClientController::class, 'index']);
    Route::middleware('permission:clients.read')->get('/clients/stats', [ClientController::class, 'stats']);
    Route::middleware('permission:clients.read')->get('/clients/{client}', [ClientController::class, 'show']);
    Route::middleware('permission:clients.read')->get('/clients/{client}/profile', [ClientController::class, 'profile']);
    Route::middleware('permission:clients.create')->post('/clients', [ClientController::class, 'store']);
    Route::middleware('permission:clients.update')->put('/clients/{client}', [ClientController::class, 'update']);
    Route::middleware('permission:clients.update')->put('/clients/{client}/notes', [ClientController::class, 'updateNotes']);
    Route::middleware('permission:clients.delete')->delete('/clients/{client}', [ClientController::class, 'destroy']);

    // Client Subscriptions
    Route::middleware('permission:client_subscriptions.read')->get('/client-subscriptions', [ClientSubscriptionController::class, 'index']);
    Route::middleware('permission:client_subscriptions.read')->get('/client-subscriptions/{client_subscription}', [ClientSubscriptionController::class, 'show']);
    Route::middleware('permission:client_subscriptions.create')->post('/client-subscriptions', [ClientSubscriptionController::class, 'store']);
    Route::middleware('permission:client_subscriptions.create')->post('/client-subscriptions/bulk', [ClientSubscriptionController::class, 'bulkStore']);
    Route::middleware('permission:client_subscriptions.update')->put('/client-subscriptions/{client_subscription}', [ClientSubscriptionController::class, 'update']);
    Route::middleware('permission:client_subscriptions.create')->post('/client-subscriptions/{client_subscription}/generate-invoice', [ClientSubscriptionController::class, 'generateInvoice']);
    Route::middleware('permission:client_subscriptions.renew')->patch('/client-subscriptions/{client_subscription}/expire-date', [ClientSubscriptionController::class, 'updateExpireDate']);
    Route::middleware('permission:client_subscriptions.delete')->delete('/client-subscriptions/{client_subscription}', [ClientSubscriptionController::class, 'destroy']);

    // Products & Services
    Route::middleware('permission:products.read')->get('/product-services', [ProductServiceController::class, 'index']);
    Route::middleware('permission:products.read')->get('/product-services/{product_service}', [ProductServiceController::class, 'show']);
    Route::middleware('permission:products.read')->get('/products', [ProductServiceController::class, 'products']);
    Route::middleware('permission:products.read')->get('/services', [ProductServiceController::class, 'services']);
    Route::middleware('permission:products.create')->post('/product-services', [ProductServiceController::class, 'store']);
    Route::middleware('permission:products.update')->put('/product-services/{product_service}', [ProductServiceController::class, 'update']);
    Route::middleware('permission:products.delete')->delete('/product-services/{product_service}', [ProductServiceController::class, 'destroy']);

    // Documents
    Route::middleware('permission:documents.read')->get('/documents', [DocumentController::class, 'index']);
    Route::middleware('permission:documents.read')->get('/documents/{document}', [DocumentController::class, 'show']);
    Route::middleware('permission:documents.create')->post('/documents', [DocumentController::class, 'store']);
    Route::middleware('permission:documents.update')->put('/documents/{document}', [DocumentController::class, 'update']);
    Route::middleware('permission:documents.delete')->delete('/documents/{document}', [DocumentController::class, 'destroy']);
    Route::middleware('permission:documents.convert')->post('/documents/{document}/convert', [DocumentController::class, 'convert']);
    Route::middleware('permission:documents.download')->get('/documents/{document}/pdf', [DocumentController::class, 'downloadPdf']);
    Route::middleware('permission:documents.send')->post('/documents/{document}/send', [DocumentController::class, 'send']);
    Route::middleware('permission:documents.send')->post('/documents/remind-unpaid', [DocumentController::class, 'remindUnpaid']);
    Route::middleware('permission:documents.create')->post('/documents/merge', [DocumentController::class, 'merge']);
    Route::middleware('permission:documents.send')->patch('/documents/{document}/submit-for-approval', [DocumentController::class, 'submitForApproval']);
    Route::middleware('permission:documents.approve')->patch('/documents/{document}/approve', [DocumentController::class, 'approve']);
    Route::middleware('permission:documents.approve')->patch('/documents/{document}/reject', [DocumentController::class, 'reject']);
    Route::middleware('permission:documents.update')->patch('/documents/{document}/cancel', [DocumentController::class, 'cancel']);
    Route::middleware('permission:documents.update')->patch('/documents/{document}/uncancel', [DocumentController::class, 'uncancel']);
    Route::middleware('permission:documents.update')->delete('/documents/{document}/items/{item}', [DocumentController::class, 'removeItem']);
    Route::middleware('permission:documents.extend_due_date')->patch('/documents/{document}/due-date', [DocumentController::class, 'updateDueDate']);
    Route::middleware('permission:documents.update')->patch('/documents/{document}/return-to-draft', [DocumentController::class, 'returnToDraft']);

    // Payments In
    Route::middleware('permission:payments_in.read')->get('/payments-in', [PaymentInController::class, 'index']);
    Route::middleware('permission:payments_in.read')->get('/payments-in/{payments_in}', [PaymentInController::class, 'show']);
    Route::middleware('permission:payments_in.create')->post('/payments-in', [PaymentInController::class, 'store']);
    Route::middleware('permission:payments_in.update')->put('/payments-in/{payments_in}', [PaymentInController::class, 'update']);
    Route::middleware('permission:payments_in.delete')->delete('/payments-in/{payments_in}', [PaymentInController::class, 'destroy']);
    Route::middleware('permission:payments_in.resend_receipt')->post('/payments-in/{payments_in}/resend-receipt', [PaymentInController::class, 'resendReceipt']);
    Route::middleware('permission:payments_in.read')->get('/payments-in/{payments_in}/receipt-pdf', [PaymentInController::class, 'downloadReceipt']);

    // Next Bill Schedule
    Route::middleware('permission:client_subscriptions.read')->get('/next-bills', [NextBillController::class, 'index']);

    // Bill Categories
    Route::middleware('permission:bills.read')->get('/bill-categories', [BillCategoryController::class, 'index']);
    Route::middleware('permission:bills.read')->get('/bill-categories/{bill_category}', [BillCategoryController::class, 'show']);
    Route::middleware('permission:bills.create')->post('/bill-categories', [BillCategoryController::class, 'store']);
    Route::middleware('permission:bills.update')->put('/bill-categories/{bill_category}', [BillCategoryController::class, 'update']);
    Route::middleware('permission:bills.delete')->delete('/bill-categories/{bill_category}', [BillCategoryController::class, 'destroy']);

    // Statutory Obligations
    Route::middleware('permission:statutories.read')->get('/statutories', [StatutoryController::class, 'index']);
    Route::middleware('permission:statutories.read')->get('/statutories/{statutory}', [StatutoryController::class, 'show']);
    Route::middleware('permission:statutories.read')->get('/statutory-schedule', [StatutoryController::class, 'schedule']);
    Route::middleware('permission:statutories.create')->post('/statutories', [StatutoryController::class, 'store']);
    Route::middleware('permission:statutories.update')->put('/statutories/{statutory}', [StatutoryController::class, 'update']);
    Route::middleware('permission:statutories.delete')->delete('/statutories/{statutory}', [StatutoryController::class, 'destroy']);

    // Bills (Statutory)
    Route::middleware('permission:bills.read')->get('/bills', [BillController::class, 'index']);
    Route::middleware('permission:bills.read')->get('/bills/{bill}', [BillController::class, 'show']);
    Route::middleware('permission:bills.create')->post('/bills', [BillController::class, 'store']);
    Route::middleware('permission:bills.update')->put('/bills/{bill}', [BillController::class, 'update']);
    Route::middleware('permission:bills.delete')->delete('/bills/{bill}', [BillController::class, 'destroy']);

    // Payments Out
    Route::middleware('permission:payments_out.read')->get('/payments-out', [PaymentOutController::class, 'index']);
    Route::middleware('permission:payments_out.read')->get('/payments-out/{payments_out}', [PaymentOutController::class, 'show']);
    Route::middleware('permission:payments_out.create')->post('/payments-out', [PaymentOutController::class, 'store']);
    Route::middleware('permission:payments_out.update')->put('/payments-out/{payments_out}', [PaymentOutController::class, 'update']);
    Route::middleware('permission:payments_out.delete')->delete('/payments-out/{payments_out}', [PaymentOutController::class, 'destroy']);

    // Expense Categories
    Route::middleware('permission:expense_categories.read')->get('/expense-categories', [ExpenseCategoryController::class, 'index']);
    Route::middleware('permission:expense_categories.read')->get('/expense-categories/{expense_category}', [ExpenseCategoryController::class, 'show']);
    Route::middleware('permission:expense_categories.create')->post('/expense-categories', [ExpenseCategoryController::class, 'store']);
    Route::middleware('permission:expense_categories.update')->put('/expense-categories/{expense_category}', [ExpenseCategoryController::class, 'update']);
    Route::middleware('permission:expense_categories.delete')->delete('/expense-categories/{expense_category}', [ExpenseCategoryController::class, 'destroy']);

    // Expenses
    Route::middleware('permission:expenses.read')->get('/expenses', [ExpenseController::class, 'index']);
    Route::middleware('permission:expenses.read')->get('/expenses/{expense}', [ExpenseController::class, 'show']);
    Route::middleware('permission:expenses.create')->post('/expenses', [ExpenseController::class, 'store']);
    Route::middleware('permission:expenses.update')->put('/expenses/{expense}', [ExpenseController::class, 'update']);
    Route::middleware('permission:expenses.delete')->delete('/expenses/{expense}', [ExpenseController::class, 'destroy']);
    // Petty cash voucher per expense (download PDF / upload signed copy)
    Route::middleware('permission:expenses.read')->get('/expenses/{expense}/voucher', [ExpenseController::class, 'downloadVoucher']);
    Route::middleware('permission:expenses.update')->post('/expenses/{expense}/voucher', [ExpenseController::class, 'uploadVoucher']);

    // Systems (reference list)
    Route::middleware('permission:systems.read')->get('/systems', [SystemController::class, 'index']);
    Route::middleware('permission:systems.read')->get('/systems/{system}', [SystemController::class, 'show']);
    Route::middleware('permission:systems.create')->post('/systems', [SystemController::class, 'store']);
    Route::middleware('permission:systems.update')->put('/systems/{system}', [SystemController::class, 'update']);
    Route::middleware('permission:systems.delete')->delete('/systems/{system}', [SystemController::class, 'destroy']);

    // Bank Accounts (reference list)
    Route::middleware('permission:bank_accounts.read')->get('/bank-accounts', [BankAccountController::class, 'index']);
    Route::middleware('permission:bank_accounts.read')->get('/bank-accounts/{bank_account}', [BankAccountController::class, 'show']);
    Route::middleware('permission:bank_accounts.create')->post('/bank-accounts', [BankAccountController::class, 'store']);
    Route::middleware('permission:bank_accounts.update')->put('/bank-accounts/{bank_account}', [BankAccountController::class, 'update']);
    Route::middleware('permission:bank_accounts.delete')->delete('/bank-accounts/{bank_account}', [BankAccountController::class, 'destroy']);

    // System Properties (reference list)
    Route::middleware('permission:system_properties.read')->get('/system-properties', [SystemPropertyController::class, 'index']);
    Route::middleware('permission:system_properties.read')->get('/system-properties/{system_property}', [SystemPropertyController::class, 'show']);
    Route::middleware('permission:system_properties.create')->post('/system-properties', [SystemPropertyController::class, 'store']);
    Route::middleware('permission:system_properties.update')->put('/system-properties/{system_property}', [SystemPropertyController::class, 'update']);
    Route::middleware('permission:system_properties.delete')->delete('/system-properties/{system_property}', [SystemPropertyController::class, 'destroy']);

    // System Records (the main data-entry CRUD that joins the above)
    Route::middleware('permission:system_records.read')->get('/system-records', [SystemRecordController::class, 'index']);
    Route::middleware('permission:system_records.read')->get('/system-records/{system_record}', [SystemRecordController::class, 'show']);
    Route::middleware('permission:system_records.create')->post('/system-records', [SystemRecordController::class, 'store']);
    Route::middleware('permission:system_records.update')->put('/system-records/{system_record}', [SystemRecordController::class, 'update']);
    Route::middleware('permission:system_records.delete')->delete('/system-records/{system_record}', [SystemRecordController::class, 'destroy']);

    // System Verifications — admin CRUD on registered systems
    Route::middleware('permission:system_verifications.read')->get('/system-verifications', [SystemVerificationController::class, 'index']);
    Route::middleware('permission:system_verifications.read')->get('/system-verifications/{system_verification}', [SystemVerificationController::class, 'show']);
    Route::middleware('permission:system_verifications.create')->post('/system-verifications', [SystemVerificationController::class, 'store']);
    Route::middleware('permission:system_verifications.update')->put('/system-verifications/{system_verification}', [SystemVerificationController::class, 'update']);
    Route::middleware('permission:system_verifications.delete')->delete('/system-verifications/{system_verification}', [SystemVerificationController::class, 'destroy']);
    Route::middleware('permission:system_verification_reports.read')->get('/system-verifications/{system_verification}/reports', [SystemVerificationController::class, 'listReports']);

    // Staff: see my assigned systems, and submit today's check-in
    Route::middleware('permission:menu.my_verifications')->get('/my-verifications', [SystemVerificationController::class, 'mine']);
    Route::middleware('permission:system_verification_reports.submit')->post('/system-verifications/{system_verification}/reports', [SystemVerificationController::class, 'submitReport']);

    // Petty Cash (single pool per tenant)
    Route::middleware('permission:petty_cash.read')->get('/petty-cash', [PettyCashController::class, 'index']);
    Route::middleware('permission:petty_cash.topup')->post('/petty-cash/transactions', [PettyCashController::class, 'storeTransaction']);
    Route::middleware('permission:petty_cash.reconcile')->post('/petty-cash/reconciliations', [PettyCashController::class, 'storeReconciliation']);
    Route::middleware('permission:petty_cash.read')->get('/petty-cash/transactions/{transaction}/voucher', [PettyCashController::class, 'downloadTransactionVoucher']);
    Route::middleware('permission:petty_cash.topup,petty_cash.reconcile')->post('/petty-cash/transactions/{transaction}/voucher', [PettyCashController::class, 'uploadTransactionVoucher']);

    // Dashboard
    Route::middleware('permission:menu.dashboard')->get('/dashboard/summary', [DashboardController::class, 'summary']);

    // Roles & Permissions (tenant)
    Route::middleware('permission:settings.users')->group(function () {
        Route::get('/roles', [RoleController::class, 'index']);
        Route::post('/roles', [RoleController::class, 'store']);
        Route::put('/roles/{role}', [RoleController::class, 'update']);
        Route::delete('/roles/{role}', [RoleController::class, 'destroy']);
    });
    Route::get('/available-permissions', [RoleController::class, 'availablePermissions']);

    // Users (Team)
    Route::middleware('permission:settings.users')->group(function () {
        Route::get('/users', [UserController::class, 'index']);
        Route::post('/users', [UserController::class, 'store']);
        Route::put('/users/{user}', [UserController::class, 'update']);
        Route::patch('/users/{user}/toggle-active', [UserController::class, 'toggleActive']);
        Route::post('/users/{user}/impersonate', [UserController::class, 'impersonate']);
    });

    // Settings
    Route::put('/settings/company', [SettingsController::class, 'updateCompany']);
    Route::post('/settings/logo', [SettingsController::class, 'uploadLogo']);
    Route::put('/settings/profile', [SettingsController::class, 'updateProfile']);
    Route::get('/settings/reminders', [SettingsController::class, 'getReminderSettings']);
    Route::put('/settings/reminders', [SettingsController::class, 'updateReminderSettings']);
    Route::get('/settings/templates', [SettingsController::class, 'getTemplates']);
    Route::put('/settings/templates', [SettingsController::class, 'updateTemplates']);
    Route::get('/settings/payment-methods', [SettingsController::class, 'getPaymentMethods']);
    Route::put('/settings/payment-methods', [SettingsController::class, 'updatePaymentMethods']);
    Route::get('/settings/subscriptions', [SettingsController::class, 'getSubscriptionSettings']);
    Route::put('/settings/subscriptions', [SettingsController::class, 'updateSubscriptionSettings']);
    Route::get('/settings/late-fee', [SettingsController::class, 'getLateFeeSettings']);
    Route::put('/settings/late-fee', [SettingsController::class, 'updateLateFeeSettings']);
    Route::get('/settings/late-fee/count', [SettingsController::class, 'getLateFeeCount']);
    Route::post('/settings/late-fee/revert', [SettingsController::class, 'revertLateFees']);
    Route::get('/settings/pesapal', [SettingsController::class, 'getPesapal']);
    Route::put('/settings/pesapal', [SettingsController::class, 'updatePesapal']);
    Route::get('/settings/whatsapp', [SettingsController::class, 'getWhatsApp']);
    Route::put('/settings/whatsapp', [SettingsController::class, 'updateWhatsApp']);

    // Email settings (tenant admin)
    Route::get('/settings/email', [EmailSettingsController::class, 'show']);
    Route::put('/settings/email', [EmailSettingsController::class, 'update']);
    Route::post('/settings/email/test', [EmailSettingsController::class, 'test']);

    // Collection
    Route::middleware('permission:menu.collection')->get('/collection/dashboard', [CollectionController::class, 'dashboard']);

    // Follow-ups
    Route::middleware('permission:menu.followups')->group(function () {
        Route::get('/followups/dashboard', [FollowupController::class, 'dashboard']);
        Route::get('/followups', [FollowupController::class, 'index']);
        Route::post('/followups', [FollowupController::class, 'store']);
        Route::post('/followups/{followup}/log-call', [FollowupController::class, 'logCall']);
        Route::patch('/followups/{followup}/cancel', [FollowupController::class, 'cancel']);
        Route::get('/followups/client/{clientId}', [FollowupController::class, 'clientHistory']);
    });

    // Satisfaction Calls
    Route::middleware('permission:menu.satisfaction_calls')->group(function () {
        Route::get('/satisfaction-calls/dashboard', [SatisfactionCallController::class, 'dashboard']);
        Route::get('/satisfaction-calls', [SatisfactionCallController::class, 'index']);
        Route::get('/satisfaction-calls/client/{clientId}', [SatisfactionCallController::class, 'clientHistory']);
        Route::middleware('permission:satisfaction_calls.log')->post('/satisfaction-calls/{satisfactionCall}/log-call', [SatisfactionCallController::class, 'logCall']);
        Route::middleware('permission:satisfaction_calls.reschedule')->patch('/satisfaction-calls/{satisfactionCall}/reschedule', [SatisfactionCallController::class, 'reschedule']);
        Route::middleware('permission:satisfaction_calls.cancel')->patch('/satisfaction-calls/{satisfactionCall}/cancel', [SatisfactionCallController::class, 'cancel']);
        Route::middleware('permission:satisfaction_calls.assign')->patch('/satisfaction-calls/{satisfactionCall}/assign', [SatisfactionCallController::class, 'assign']);
        Route::get('/satisfaction-calls/appointments', [SatisfactionCallController::class, 'appointments']);
        Route::patch('/satisfaction-calls/{satisfactionCall}/appointment', [SatisfactionCallController::class, 'updateAppointment']);
    });

    // Automation
    Route::middleware('permission:menu.automation')->prefix('automation')->group(function () {
        Route::get('/summary', [AutomationController::class, 'summary']);
        Route::get('/cron-logs', [AutomationController::class, 'cronLogs']);
        Route::get('/communication-logs', [AutomationController::class, 'communicationLogs']);
    });

    // Reports
    Route::prefix('reports')->group(function () {
        Route::middleware('permission:reports.revenue')->get('/revenue-summary', [ReportController::class, 'revenueSummary']);
        Route::middleware('permission:reports.aging')->get('/outstanding-aging', [ReportController::class, 'outstandingAging']);
        Route::middleware('permission:reports.client_statement')->get('/client-statement', [ReportController::class, 'clientStatement']);
        Route::middleware('permission:reports.payment_collection')->get('/payment-collection', [ReportController::class, 'paymentCollection']);
        Route::middleware('permission:reports.expense')->get('/expense-report', [ReportController::class, 'expenseReport']);
        Route::middleware('permission:reports.system_records')->get('/system-records-report', [ReportController::class, 'systemRecordsReport']);
        Route::middleware('permission:reports.system_verifications')->get('/system-verifications-report', [ReportController::class, 'systemVerificationsReport']);
        Route::middleware('permission:reports.profit_loss')->get('/profit-loss', [ReportController::class, 'profitLoss']);
        Route::middleware('permission:reports.statutory')->get('/statutory-compliance', [ReportController::class, 'statutoryCompliance']);
        Route::middleware('permission:reports.subscription')->get('/subscription-report', [ReportController::class, 'subscriptionReport']);
        Route::middleware('permission:reports.collection')->get('/collection-effectiveness', [ReportController::class, 'collectionEffectiveness']);
        Route::middleware('permission:reports.satisfaction')->get('/satisfaction-calls', [ReportController::class, 'satisfactionReport']);
        Route::middleware('permission:reports.communication')->get('/communication-log', [ReportController::class, 'communicationLog']);
    });

    // Broadcasts
    Route::get('/broadcasts', [BroadcastController::class, 'index']);
    Route::post('/broadcasts', [BroadcastController::class, 'send']);

    // WhatsApp Campaigns
    Route::middleware('permission:whatsapp_campaigns.read')->get('/whatsapp-campaigns', [\App\Http\Controllers\WhatsappCampaignController::class, 'index']);
    Route::middleware('permission:whatsapp_campaigns.create')->post('/whatsapp-campaigns', [\App\Http\Controllers\WhatsappCampaignController::class, 'store']);
    Route::middleware('permission:whatsapp_campaigns.update')->put('/whatsapp-campaigns/{whatsappCampaign}', [\App\Http\Controllers\WhatsappCampaignController::class, 'update']);
    Route::middleware('permission:whatsapp_campaigns.delete')->delete('/whatsapp-campaigns/{whatsappCampaign}', [\App\Http\Controllers\WhatsappCampaignController::class, 'destroy']);

    // Marketing Services (shared picklist for field visits & whatsapp contacts)
    Route::middleware('permission:marketing_services.read')->get('/marketing-services', [\App\Http\Controllers\MarketingServiceController::class, 'index']);
    Route::middleware('permission:marketing_services.create')->post('/marketing-services', [\App\Http\Controllers\MarketingServiceController::class, 'store']);
    Route::middleware('permission:marketing_services.update')->put('/marketing-services/{marketingService}', [\App\Http\Controllers\MarketingServiceController::class, 'update']);
    Route::middleware('permission:marketing_services.delete')->delete('/marketing-services/{marketingService}', [\App\Http\Controllers\MarketingServiceController::class, 'destroy']);
    Route::middleware('permission:marketing_services.update')->post('/marketing-services/reorder', [\App\Http\Controllers\MarketingServiceController::class, 'reorder']);

    // WhatsApp Contacts (Marketing Pipeline)
    Route::middleware('permission:whatsapp_contacts.read')->get('/whatsapp-contacts/stats', [\App\Http\Controllers\WhatsappContactController::class, 'stats']);
    Route::middleware('permission:whatsapp_contacts.read')->get('/whatsapp-contacts', [\App\Http\Controllers\WhatsappContactController::class, 'index']);
    Route::middleware('permission:whatsapp_contacts.create')->post('/whatsapp-contacts', [\App\Http\Controllers\WhatsappContactController::class, 'store']);
    Route::middleware('permission:whatsapp_contacts.view_all')->post('/whatsapp-contacts/claim-bulk', [\App\Http\Controllers\WhatsappContactController::class, 'claimBulk']);
    Route::middleware('permission:whatsapp_contacts.update')->put('/whatsapp-contacts/{whatsappContact}', [\App\Http\Controllers\WhatsappContactController::class, 'update']);
    Route::middleware('permission:whatsapp_contacts.delete')->delete('/whatsapp-contacts/{whatsappContact}', [\App\Http\Controllers\WhatsappContactController::class, 'destroy']);
    Route::middleware('permission:whatsapp_contacts.convert')->post('/whatsapp-contacts/{whatsappContact}/convert', [\App\Http\Controllers\WhatsappContactController::class, 'convertToClient']);
    Route::middleware('permission:whatsapp_contacts.update')->post('/whatsapp-contacts/{whatsappContact}/claim', [\App\Http\Controllers\WhatsappContactController::class, 'claim']);
    Route::middleware('permission:whatsapp_contacts.update')->post('/whatsapp-contacts/{whatsappContact}/unclaim', [\App\Http\Controllers\WhatsappContactController::class, 'unclaim']);
    Route::middleware('permission:whatsapp_contacts.view_all')->post('/whatsapp-contacts/{whatsappContact}/assign', [\App\Http\Controllers\WhatsappContactController::class, 'assign']);
    Route::middleware('permission:whatsapp_contacts.log')->get('/whatsapp-contacts/{whatsappContact}/followups', [\App\Http\Controllers\WhatsappFollowupController::class, 'index']);
    Route::middleware('permission:whatsapp_contacts.log')->post('/whatsapp-contacts/{whatsappContact}/followups', [\App\Http\Controllers\WhatsappFollowupController::class, 'store']);
    Route::middleware('permission:whatsapp_contacts.log')->delete('/whatsapp-contacts/{whatsappContact}/followups/{followup}', [\App\Http\Controllers\WhatsappFollowupController::class, 'destroy']);

    // ── Hosting (WHM/cPanel provisioning) ────────────────────────────────────
    Route::middleware('permission:hosting.settings')->group(function () {
        Route::get('/servers',                    [\App\Http\Controllers\ServerController::class, 'index']);
        Route::post('/servers',                   [\App\Http\Controllers\ServerController::class, 'store']);
        Route::put('/servers/{server}',           [\App\Http\Controllers\ServerController::class, 'update']);
        Route::delete('/servers/{server}',        [\App\Http\Controllers\ServerController::class, 'destroy']);
        Route::post('/servers/{server}/test',     [\App\Http\Controllers\ServerController::class, 'test']);
    });
    Route::middleware('permission:hosting.read')->get('/hosting-accounts', [\App\Http\Controllers\HostingAccountController::class, 'index']);
    Route::middleware('permission:hosting.read')->get('/hosting-accounts/{hostingAccount}/logs', [\App\Http\Controllers\HostingAccountController::class, 'logs']);
    Route::middleware('permission:hosting.create')->post('/client-subscriptions/{clientSubscription}/provision', [\App\Http\Controllers\HostingAccountController::class, 'provision']);
    Route::middleware('permission:hosting.suspend')->post('/hosting-accounts/{hostingAccount}/suspend', [\App\Http\Controllers\HostingAccountController::class, 'suspend']);
    Route::middleware('permission:hosting.suspend')->post('/hosting-accounts/{hostingAccount}/unsuspend', [\App\Http\Controllers\HostingAccountController::class, 'unsuspend']);
    Route::middleware('permission:hosting.terminate')->post('/hosting-accounts/{hostingAccount}/terminate', [\App\Http\Controllers\HostingAccountController::class, 'terminate']);
    Route::middleware('permission:hosting.change_package')->post('/hosting-accounts/{hostingAccount}/change-package', [\App\Http\Controllers\HostingAccountController::class, 'changePackage']);
    Route::middleware('permission:hosting.sso')->post('/hosting-accounts/{hostingAccount}/sso', [\App\Http\Controllers\HostingAccountController::class, 'sso']);

    // ── Domains (.tz registrar) ──────────────────────────────────────────────
    Route::middleware('permission:domains.read')->group(function () {
        Route::get('/domains/check',            [\App\Http\Controllers\DomainController::class, 'check']);
        Route::get('/domains/stats',            [\App\Http\Controllers\DomainController::class, 'stats']);
        Route::get('/domains',                  [\App\Http\Controllers\DomainController::class, 'index']);
        Route::get('/domains/{domain}',         [\App\Http\Controllers\DomainController::class, 'show']);
        Route::get('/domains/{domain}/logs',    [\App\Http\Controllers\DomainController::class, 'logs']);
    });
    Route::middleware('permission:domains.create')->post('/domains/order', [\App\Http\Controllers\DomainController::class, 'order']);
    Route::middleware('permission:domains.renew')->post('/domains/{domain}/renew', [\App\Http\Controllers\DomainController::class, 'renew']);
    Route::middleware('permission:domains.renew')->put('/domains/{domain}/auto-renew', [\App\Http\Controllers\DomainController::class, 'setAutoRenew']);
    Route::middleware('permission:domains.read')->get('/domains/{domain}/nameservers', [\App\Http\Controllers\DomainController::class, 'nameservers']);
    Route::middleware('permission:domains.manage_dns')->put('/domains/{domain}/nameservers', [\App\Http\Controllers\DomainController::class, 'updateNameservers']);
    Route::middleware('permission:domains.transfer')->get('/domains/{domain}/auth-info', [\App\Http\Controllers\DomainController::class, 'authInfo']);
    Route::middleware('permission:domains.settings')->group(function () {
        Route::get('/registrar-accounts',                       [\App\Http\Controllers\RegistrarAccountController::class, 'index']);
        Route::post('/registrar-accounts',                      [\App\Http\Controllers\RegistrarAccountController::class, 'store']);
        Route::put('/registrar-accounts/{registrarAccount}',    [\App\Http\Controllers\RegistrarAccountController::class, 'update']);
        Route::delete('/registrar-accounts/{registrarAccount}', [\App\Http\Controllers\RegistrarAccountController::class, 'destroy']);
        Route::post('/registrar-accounts/{registrarAccount}/test', [\App\Http\Controllers\RegistrarAccountController::class, 'test']);
        Route::get('/domain-tlds',                  [\App\Http\Controllers\DomainTldController::class, 'index']);
        Route::post('/domain-tlds',                 [\App\Http\Controllers\DomainTldController::class, 'store']);
        Route::put('/domain-tlds/{domainTld}',      [\App\Http\Controllers\DomainTldController::class, 'update']);
        Route::delete('/domain-tlds/{domainTld}',   [\App\Http\Controllers\DomainTldController::class, 'destroy']);
    });

    // ── Support Tickets ──────────────────────────────────────────────────────
    Route::middleware('permission:tickets.read')->group(function () {
        Route::get('/tickets',          [\App\Http\Controllers\TicketController::class, 'index']);
        Route::get('/tickets/stats',    [\App\Http\Controllers\TicketController::class, 'stats']);
        Route::get('/tickets/{ticket}', [\App\Http\Controllers\TicketController::class, 'show']);
    });
    Route::middleware('permission:tickets.reply')->post('/tickets/{ticket}/reply', [\App\Http\Controllers\TicketController::class, 'reply']);
    Route::middleware('permission:tickets.manage')->post('/tickets/{ticket}/status', [\App\Http\Controllers\TicketController::class, 'updateStatus']);
    Route::middleware('permission:tickets.manage')->post('/tickets/{ticket}/assign', [\App\Http\Controllers\TicketController::class, 'assign']);

    // ── Client Credit (wallet) ───────────────────────────────────────────────
    Route::middleware('permission:credit.manage')->group(function () {
        Route::get('/clients/{client}/credit',        [\App\Http\Controllers\ClientCreditController::class, 'show']);
        Route::post('/clients/{client}/credit/adjust', [\App\Http\Controllers\ClientCreditController::class, 'adjust']);
        Route::post('/documents/{document}/apply-credit', [\App\Http\Controllers\ClientCreditController::class, 'applyToInvoice']);
    });

    // ── Announcements ────────────────────────────────────────────────────────
    Route::middleware('permission:announcements.manage')->group(function () {
        Route::get('/announcements',                   [\App\Http\Controllers\AnnouncementController::class, 'index']);
        Route::post('/announcements',                  [\App\Http\Controllers\AnnouncementController::class, 'store']);
        Route::put('/announcements/{announcement}',    [\App\Http\Controllers\AnnouncementController::class, 'update']);
        Route::delete('/announcements/{announcement}', [\App\Http\Controllers\AnnouncementController::class, 'destroy']);
    });

    // ── Field Marketing (Door-to-Door) ───────────────────────────────────────
    Route::middleware('permission:field_sessions.read')->get('/field-visits-report', [\App\Http\Controllers\FieldMarketingController::class, 'allVisits']);
    Route::middleware('permission:field_sessions.read')->get('/field-sessions', [\App\Http\Controllers\FieldMarketingController::class, 'sessions']);
    Route::middleware('permission:field_sessions.read')->get('/field-sessions/{fieldSession}', [\App\Http\Controllers\FieldMarketingController::class, 'sessionDetail']);
    Route::middleware('permission:field_sessions.create')->post('/field-sessions', [\App\Http\Controllers\FieldMarketingController::class, 'storeSession']);
    Route::middleware('permission:field_sessions.update')->put('/field-sessions/{fieldSession}', [\App\Http\Controllers\FieldMarketingController::class, 'updateSession']);
    Route::middleware('permission:field_sessions.delete')->delete('/field-sessions/{fieldSession}', [\App\Http\Controllers\FieldMarketingController::class, 'destroySession']);

    Route::middleware('permission:field_visits.create')->post('/field-sessions/{fieldSession}/visits', [\App\Http\Controllers\FieldMarketingController::class, 'storeVisit']);
    Route::middleware('permission:field_visits.update')->put('/field-sessions/{fieldSession}/visits/{visit}', [\App\Http\Controllers\FieldMarketingController::class, 'updateVisit']);
    Route::middleware('permission:field_visits.delete')->delete('/field-sessions/{fieldSession}/visits/{visit}', [\App\Http\Controllers\FieldMarketingController::class, 'destroyVisit']);
    Route::middleware('permission:field_visits.convert')->post('/field-sessions/{fieldSession}/visits/{visit}/convert', [\App\Http\Controllers\FieldMarketingController::class, 'convertVisit']);
    Route::middleware('permission:field_visits.log')->get('/field-visits/{visit}/followups', [\App\Http\Controllers\FieldFollowupController::class, 'index']);
    Route::middleware('permission:field_visits.log')->post('/field-visits/{visit}/followups', [\App\Http\Controllers\FieldFollowupController::class, 'store']);
    Route::middleware('permission:field_visits.log')->delete('/field-visits/{visit}/followups/{followup}', [\App\Http\Controllers\FieldFollowupController::class, 'destroy']);

    Route::middleware('permission:field_targets.read')->get('/field-targets', [\App\Http\Controllers\FieldMarketingController::class, 'targets']);
    Route::middleware('permission:field_targets.update')->post('/field-targets', [\App\Http\Controllers\FieldMarketingController::class, 'setTarget']);

    Route::middleware('permission:field_sessions.read')->get('/field-stats', [\App\Http\Controllers\FieldMarketingController::class, 'stats']);

    // Social Media
    Route::middleware('permission:social.read')->get('/social/platforms', [\App\Http\Controllers\SocialMediaController::class, 'platformSettings']);
    Route::middleware('permission:social.targets')->post('/social/platforms', [\App\Http\Controllers\SocialMediaController::class, 'storePlatform']);
    Route::middleware('permission:social.targets')->put('/social/platforms/{socialPlatform}', [\App\Http\Controllers\SocialMediaController::class, 'updatePlatform']);
    Route::middleware('permission:social.targets')->delete('/social/platforms/{socialPlatform}', [\App\Http\Controllers\SocialMediaController::class, 'destroyPlatform']);
    Route::middleware('permission:social.read')->get('/social/posts', [\App\Http\Controllers\SocialMediaController::class, 'posts']);
    Route::middleware('permission:social.read')->get('/social/weekly-summary', [\App\Http\Controllers\SocialMediaController::class, 'weeklySummary']);
    Route::middleware('permission:social.read')->get('/social/targets', [\App\Http\Controllers\SocialMediaController::class, 'targets']);
    Route::middleware('permission:social.create')->post('/social/posts', [\App\Http\Controllers\SocialMediaController::class, 'storePost']);
    Route::middleware('permission:social.update')->put('/social/posts/{socialPost}', [\App\Http\Controllers\SocialMediaController::class, 'updatePost']);
    Route::middleware('permission:social.update')->patch('/social/posts/{socialPost}/design', [\App\Http\Controllers\SocialMediaController::class, 'updateDesign']);
    Route::middleware('permission:social.update')->patch('/social/posts/{socialPost}/content', [\App\Http\Controllers\SocialMediaController::class, 'updateContent']);
    Route::middleware('permission:social.update')->patch('/social/posts/{socialPost}/platform/{platform}', [\App\Http\Controllers\SocialMediaController::class, 'togglePlatform']);
    Route::middleware('permission:social.delete')->delete('/social/posts/{socialPost}', [\App\Http\Controllers\SocialMediaController::class, 'destroyPost']);
    Route::middleware('permission:social.targets')->post('/social/targets', [\App\Http\Controllers\SocialMediaController::class, 'upsertTarget']);
    Route::middleware('permission:social.targets')->delete('/social/targets/{socialTarget}', [\App\Http\Controllers\SocialMediaController::class, 'destroyTarget']);
    Route::middleware('permission:social.read')->get('/social/design-orders', [\App\Http\Controllers\SocialMediaController::class, 'designOrders']);
    Route::middleware('permission:social.create')->post('/social/design-orders', [\App\Http\Controllers\SocialMediaController::class, 'storeDesignOrder']);
    Route::middleware('permission:social.update')->put('/social/design-orders/{clientDesignOrder}', [\App\Http\Controllers\SocialMediaController::class, 'updateDesignOrder']);
    Route::middleware('permission:social.delete')->delete('/social/design-orders/{clientDesignOrder}', [\App\Http\Controllers\SocialMediaController::class, 'destroyDesignOrder']);

    // Served Customers
    Route::middleware('permission:served.read')->get('/served/services', [\App\Http\Controllers\ServedCustomersController::class, 'services']);
    Route::middleware('permission:served.settings')->post('/served/services', [\App\Http\Controllers\ServedCustomersController::class, 'storeService']);
    Route::middleware('permission:served.settings')->put('/served/services/{servedService}', [\App\Http\Controllers\ServedCustomersController::class, 'updateService']);
    Route::middleware('permission:served.settings')->delete('/served/services/{servedService}', [\App\Http\Controllers\ServedCustomersController::class, 'destroyService']);
    Route::middleware('permission:served.read')->get('/served/customers', [\App\Http\Controllers\ServedCustomersController::class, 'customers']);
    Route::middleware('permission:served.create')->post('/served/customers', [\App\Http\Controllers\ServedCustomersController::class, 'storeCustomer']);
    Route::middleware('permission:served.update')->put('/served/customers/{servedCustomer}', [\App\Http\Controllers\ServedCustomersController::class, 'updateCustomer']);
    Route::middleware('permission:served.delete')->delete('/served/customers/{servedCustomer}', [\App\Http\Controllers\ServedCustomersController::class, 'destroyCustomer']);
    Route::middleware('permission:served.create')->post('/served/customers/{servedCustomer}/feedback', [\App\Http\Controllers\ServedCustomersController::class, 'storeFeedback']);
    Route::middleware('permission:served.delete')->delete('/served/customers/{servedCustomer}/feedback/{feedback}', [\App\Http\Controllers\ServedCustomersController::class, 'destroyFeedback']);
    Route::middleware('permission:served.read')->get('/served/target', [\App\Http\Controllers\ServedCustomersController::class, 'target']);
    Route::middleware('permission:served.settings')->post('/served/target', [\App\Http\Controllers\ServedCustomersController::class, 'upsertTarget']);
    Route::middleware('permission:served.read')->get('/served/weekly-summary', [\App\Http\Controllers\ServedCustomersController::class, 'weeklyTargetSummary']);
    Route::middleware('permission:served.read')->get('/served/report', [\App\Http\Controllers\ServedCustomersController::class, 'report']);

    // ── Staff Reports ────────────────────────────────────────────────────────
    Route::get('/staff-reports/dashboard',               [\App\Http\Controllers\StaffReportsController::class, 'dashboard']);
    Route::get('/staff-reports/settings',                [\App\Http\Controllers\StaffReportSettingsController::class, 'show']);
    Route::put('/staff-reports/settings',                [\App\Http\Controllers\StaffReportSettingsController::class, 'update']);
    Route::get('/staff-reports/supervisors',             [\App\Http\Controllers\StaffSupervisorController::class, 'index']);
    Route::put('/staff-reports/supervisors/{userId}',    [\App\Http\Controllers\StaffSupervisorController::class, 'update']);
    Route::get('/staff-reports',                         [\App\Http\Controllers\StaffReportsController::class, 'index']);
    Route::post('/staff-reports',                        [\App\Http\Controllers\StaffReportsController::class, 'store']);
    Route::put('/staff-reports/{staffReport}',           [\App\Http\Controllers\StaffReportsController::class, 'update']);
    Route::delete('/staff-reports/{staffReport}',        [\App\Http\Controllers\StaffReportsController::class, 'destroy']);
    Route::post('/staff-reports/{staffReport}/review',   [\App\Http\Controllers\StaffReportsController::class, 'review']);

    // ── Staff Targets & Commission ────────────────────────────────────────────
    Route::get('/staff-targets/summary',                          [\App\Http\Controllers\StaffTargetsController::class, 'summary']);
    Route::get('/staff-targets',                                  [\App\Http\Controllers\StaffTargetsController::class, 'index']);
    Route::post('/staff-targets',                                 [\App\Http\Controllers\StaffTargetsController::class, 'store']);
    Route::put('/staff-targets/{staffTarget}',                    [\App\Http\Controllers\StaffTargetsController::class, 'update']);
    Route::delete('/staff-targets/{staffTarget}',                 [\App\Http\Controllers\StaffTargetsController::class, 'destroy']);
    Route::post('/staff-targets/{staffTarget}/self-report',       [\App\Http\Controllers\StaffTargetsController::class, 'selfReport']);
    Route::post('/staff-targets/{staffTarget}/verify',            [\App\Http\Controllers\StaffTargetsController::class, 'verify']);

    // Client Portal Users (tenant admin manages portal access for clients)
    Route::middleware('permission:clients.update')->group(function () {
        Route::get('/clients/{client}/portal-users', [ClientPortalUserController::class, 'index']);
        Route::post('/clients/{client}/portal-users', [ClientPortalUserController::class, 'store']);
        Route::put('/clients/{client}/portal-users/{portalUser}', [ClientPortalUserController::class, 'update']);
        Route::delete('/clients/{client}/portal-users/{portalUser}', [ClientPortalUserController::class, 'destroy']);
    });
    Route::middleware('permission:clients.portal_login')
        ->post('/clients/{client}/portal-login', [ClientPortalUserController::class, 'impersonate']);
    Route::middleware('permission:clients.portal_password')
        ->post('/clients/{client}/portal-password', [ClientPortalUserController::class, 'changePassword']);

    // SMS (tenant)
    Route::get('/sms/packages', [SmsPurchaseController::class, 'packages']);
    Route::get('/sms/balance', [SmsPurchaseController::class, 'balance']);
    Route::post('/sms/checkout', [SmsPurchaseController::class, 'checkout']);
    Route::get('/sms/purchases/{smsPurchase}/status', [SmsPurchaseController::class, 'checkStatus']);
    Route::get('/sms/purchases', [SmsPurchaseController::class, 'history']);
    Route::post('/sms/purchases/{smsPurchase}/retry', [SmsPurchaseController::class, 'retryPayment']);
    Route::get('/sms/purchases/{smsPurchase}/receipt', [SmsPurchaseController::class, 'downloadReceipt']);
    Route::get('/sms/purchases/{smsPurchase}/invoice', [SmsPurchaseController::class, 'downloadInvoice']);
    Route::post('/sms/request-activation', [SmsPurchaseController::class, 'requestActivation']);
});

// Client Portal routes
Route::middleware(['auth:sanctum', 'client_portal'])->prefix('portal')->group(function () {
    Route::get('/dashboard', [PortalDashboardController::class, 'summary']);
    Route::get('/documents', [PortalDocumentController::class, 'index']);
    Route::get('/documents/{document}', [PortalDocumentController::class, 'show']);
    Route::get('/documents/{document}/pdf', [PortalDocumentController::class, 'downloadPdf']);
    Route::post('/documents/{document}/resend', [PortalDocumentController::class, 'resend']);
    Route::get('/payments', [PortalPaymentController::class, 'index']);
    Route::get('/payments/{payment}/receipt', [PortalPaymentController::class, 'downloadReceipt']);
    Route::get('/statement', [PortalStatementController::class, 'index']);
    Route::get('/products-services', [PortalProductServiceController::class, 'index']);
    Route::get('/subscriptions', [PortalSubscriptionController::class, 'index']);
    Route::get('/hosting', [\App\Http\Controllers\Portal\PortalHostingController::class, 'index']);
    Route::post('/hosting/{hostingAccount}/sso', [\App\Http\Controllers\Portal\PortalHostingController::class, 'sso']);
    Route::get('/hosting/{hostingAccount}', [\App\Http\Controllers\Portal\PortalHostingController::class, 'show']);
    Route::post('/hosting/{hostingAccount}/refresh-usage', [\App\Http\Controllers\Portal\PortalHostingController::class, 'refreshUsage']);
    Route::post('/hosting/{hostingAccount}/change-password', [\App\Http\Controllers\Portal\PortalHostingController::class, 'changePassword']);
    Route::post('/hosting/{hostingAccount}/request-cancellation', [\App\Http\Controllers\Portal\PortalHostingController::class, 'requestCancellation']);
    Route::get('/hosting/{hostingAccount}/upgrade-options', [\App\Http\Controllers\Portal\PortalHostingController::class, 'upgradeOptions']);
    Route::post('/hosting/{hostingAccount}/upgrade', [\App\Http\Controllers\Portal\PortalHostingController::class, 'upgrade']);
    Route::get('/domains', [\App\Http\Controllers\Portal\PortalDomainController::class, 'index']);
    Route::get('/domains/check', [\App\Http\Controllers\Portal\PortalDomainController::class, 'check']);
    Route::post('/domains/order', [\App\Http\Controllers\Portal\PortalDomainController::class, 'order']);
    Route::get('/domains/{domain}', [\App\Http\Controllers\Portal\PortalDomainController::class, 'show']);
    Route::post('/domains/{domain}/renew', [\App\Http\Controllers\Portal\PortalDomainController::class, 'renew']);
    Route::post('/domains/{domain}/epp-code', [\App\Http\Controllers\Portal\PortalDomainController::class, 'eppCode']);
    Route::put('/domains/{domain}/auto-renew', [\App\Http\Controllers\Portal\PortalDomainController::class, 'setAutoRenew']);
    Route::get('/tickets',                  [\App\Http\Controllers\Portal\PortalTicketController::class, 'index']);
    Route::post('/tickets',                 [\App\Http\Controllers\Portal\PortalTicketController::class, 'store']);
    Route::get('/tickets/{ticket}',         [\App\Http\Controllers\Portal\PortalTicketController::class, 'show']);
    Route::post('/tickets/{ticket}/reply',  [\App\Http\Controllers\Portal\PortalTicketController::class, 'reply']);
    Route::post('/tickets/{ticket}/close',  [\App\Http\Controllers\Portal\PortalTicketController::class, 'close']);
    Route::get('/catalog',  [\App\Http\Controllers\Portal\PortalOrderController::class, 'catalog']);
    Route::get('/domain-tlds', [\App\Http\Controllers\Portal\PortalOrderController::class, 'tlds']);
    Route::get('/domain-addons', [\App\Http\Controllers\Portal\PortalOrderController::class, 'domainAddons']);
    Route::post('/orders',  [\App\Http\Controllers\Portal\PortalOrderController::class, 'store']);
    Route::get('/credit',                       [\App\Http\Controllers\Portal\PortalCreditController::class, 'show']);
    Route::post('/credit/topup',                [\App\Http\Controllers\Portal\PortalCreditController::class, 'topup']);
    Route::post('/documents/{document}/apply-credit', [\App\Http\Controllers\Portal\PortalCreditController::class, 'applyToInvoice']);
    Route::get('/announcements', [\App\Http\Controllers\Portal\PortalAnnouncementController::class, 'index']);
    Route::post('/subscriptions/{clientSubscription}/generate-invoice', [PortalSubscriptionController::class, 'generateInvoice']);
    Route::post('/documents/{document}/pay', [InvoicePaymentController::class, 'checkout']);
    Route::get('/documents/{document}/pay/{payment}/status', [InvoicePaymentController::class, 'status']);
    Route::get('/profile', [PortalProfileController::class, 'show']);
    Route::put('/profile', [PortalProfileController::class, 'update']);
    Route::post('/profile/change-password', [PortalProfileController::class, 'changePassword']);
    Route::get('/users', [PortalProfileController::class, 'listUsers']);
    Route::post('/users', [PortalProfileController::class, 'storeUser']);
    Route::put('/users/{portalUser}', [PortalProfileController::class, 'updateUser']);
    Route::delete('/users/{portalUser}', [PortalProfileController::class, 'deleteUser']);
});

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
use App\Http\Controllers\BroadcastController;
use App\Http\Controllers\EmailSettingsController;
use App\Http\Controllers\ReportController;
use App\Http\Controllers\ExpenseCategoryController;
use App\Http\Controllers\ExpenseController;
use App\Http\Controllers\NotificationController;
use App\Http\Controllers\AutomationController;
use App\Http\Controllers\CollectionController;
use App\Http\Controllers\FollowupController;
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
use App\Http\Controllers\PesapalWebhookController;
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
Route::post('/auth/reset-password', [PasswordResetController::class, 'resetPassword']);

// Pesapal webhooks (public, no auth)
Route::match(['get', 'post'], '/pesapal/ipn', [PesapalWebhookController::class, 'ipn']);
Route::get('/pesapal/callback', [PesapalWebhookController::class, 'callback']);

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

    // Impersonate tenant
    Route::post('/tenants/{tenant}/impersonate', [TenantController::class, 'impersonate']);

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
    Route::middleware('permission:clients.read')->get('/clients/{client}', [ClientController::class, 'show']);
    Route::middleware('permission:clients.read')->get('/clients/{client}/profile', [ClientController::class, 'profile']);
    Route::middleware('permission:clients.create')->post('/clients', [ClientController::class, 'store']);
    Route::middleware('permission:clients.update')->put('/clients/{client}', [ClientController::class, 'update']);
    Route::middleware('permission:clients.delete')->delete('/clients/{client}', [ClientController::class, 'destroy']);

    // Client Subscriptions
    Route::middleware('permission:client_subscriptions.read')->get('/client-subscriptions', [ClientSubscriptionController::class, 'index']);
    Route::middleware('permission:client_subscriptions.read')->get('/client-subscriptions/{client_subscription}', [ClientSubscriptionController::class, 'show']);
    Route::middleware('permission:client_subscriptions.create')->post('/client-subscriptions', [ClientSubscriptionController::class, 'store']);
    Route::middleware('permission:client_subscriptions.update')->put('/client-subscriptions/{client_subscription}', [ClientSubscriptionController::class, 'update']);
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

    // Payments In
    Route::middleware('permission:payments_in.read')->get('/payments-in', [PaymentInController::class, 'index']);
    Route::middleware('permission:payments_in.read')->get('/payments-in/{payments_in}', [PaymentInController::class, 'show']);
    Route::middleware('permission:payments_in.create')->post('/payments-in', [PaymentInController::class, 'store']);
    Route::middleware('permission:payments_in.update')->put('/payments-in/{payments_in}', [PaymentInController::class, 'update']);
    Route::middleware('permission:payments_in.delete')->delete('/payments-in/{payments_in}', [PaymentInController::class, 'destroy']);
    Route::middleware('permission:payments_in.resend_receipt')->post('/payments-in/{payments_in}/resend-receipt', [PaymentInController::class, 'resendReceipt']);

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
        Route::middleware('permission:reports.profit_loss')->get('/profit-loss', [ReportController::class, 'profitLoss']);
        Route::middleware('permission:reports.statutory')->get('/statutory-compliance', [ReportController::class, 'statutoryCompliance']);
        Route::middleware('permission:reports.subscription')->get('/subscription-report', [ReportController::class, 'subscriptionReport']);
        Route::middleware('permission:reports.collection')->get('/collection-effectiveness', [ReportController::class, 'collectionEffectiveness']);
        Route::middleware('permission:reports.communication')->get('/communication-log', [ReportController::class, 'communicationLog']);
    });

    // Broadcasts
    Route::get('/broadcasts', [BroadcastController::class, 'index']);
    Route::post('/broadcasts', [BroadcastController::class, 'send']);

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

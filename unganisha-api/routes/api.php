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
use App\Http\Controllers\Admin\TenantSubscriptionController;
use App\Http\Controllers\EmailSettingsController;
use App\Http\Controllers\ExpenseCategoryController;
use App\Http\Controllers\ExpenseController;
use App\Http\Controllers\NotificationController;
use App\Http\Controllers\AutomationController;
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
});

// Tenant-scoped routes
Route::middleware(['auth:sanctum', 'tenant'])->group(function () {

    // Clients
    Route::apiResource('clients', ClientController::class);
    Route::get('/clients/{client}/profile', [ClientController::class, 'profile']);

    // Client Subscriptions
    Route::apiResource('client-subscriptions', ClientSubscriptionController::class);

    // Products & Services
    Route::apiResource('product-services', ProductServiceController::class);
    Route::get('/products', [ProductServiceController::class, 'products']);
    Route::get('/services', [ProductServiceController::class, 'services']);

    // Documents
    Route::apiResource('documents', DocumentController::class);
    Route::post('/documents/{document}/convert', [DocumentController::class, 'convert']);
    Route::get('/documents/{document}/pdf', [DocumentController::class, 'downloadPdf']);
    Route::post('/documents/{document}/send', [DocumentController::class, 'send']);
    Route::post('/documents/remind-unpaid', [DocumentController::class, 'remindUnpaid']);

    // Payments In
    Route::apiResource('payments-in', PaymentInController::class)->only(['index', 'store', 'show', 'update', 'destroy']);

    // Next Bill Schedule
    Route::get('/next-bills', [NextBillController::class, 'index']);
    Route::post('/payments-in/{payments_in}/resend-receipt', [PaymentInController::class, 'resendReceipt']);

    // Bill Categories
    Route::apiResource('bill-categories', BillCategoryController::class);

    // Statutory Obligations
    Route::apiResource('statutories', StatutoryController::class);
    Route::get('/statutory-schedule', [StatutoryController::class, 'schedule']);

    // Bills (Statutory)
    Route::apiResource('bills', BillController::class);

    // Payments Out
    Route::apiResource('payments-out', PaymentOutController::class);

    // Expense Categories
    Route::apiResource('expense-categories', ExpenseCategoryController::class);

    // Expenses
    Route::apiResource('expenses', ExpenseController::class);

    // Dashboard
    Route::get('/dashboard/summary', [DashboardController::class, 'summary']);

    // Users (Team)
    Route::apiResource('users', UserController::class)->except(['destroy', 'show']);
    Route::patch('/users/{user}/toggle-active', [UserController::class, 'toggleActive']);

    // Settings
    Route::put('/settings/company', [SettingsController::class, 'updateCompany']);
    Route::post('/settings/logo', [SettingsController::class, 'uploadLogo']);
    Route::put('/settings/profile', [SettingsController::class, 'updateProfile']);
    Route::get('/settings/reminders', [SettingsController::class, 'getReminderSettings']);
    Route::put('/settings/reminders', [SettingsController::class, 'updateReminderSettings']);
    Route::get('/settings/templates', [SettingsController::class, 'getTemplates']);
    Route::put('/settings/templates', [SettingsController::class, 'updateTemplates']);

    // Email settings (tenant admin)
    Route::get('/settings/email', [EmailSettingsController::class, 'show']);
    Route::put('/settings/email', [EmailSettingsController::class, 'update']);
    Route::post('/settings/email/test', [EmailSettingsController::class, 'test']);

    // Automation
    Route::prefix('automation')->group(function () {
        Route::get('/summary', [AutomationController::class, 'summary']);
        Route::get('/cron-logs', [AutomationController::class, 'cronLogs']);
        Route::get('/communication-logs', [AutomationController::class, 'communicationLogs']);
    });

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

<?php

use App\Http\Controllers\Admin\AdminUserController;
use App\Http\Controllers\Admin\DashboardController as AdminDashboardController;
use App\Http\Controllers\Admin\EmailSettingsController as AdminEmailSettingsController;
use App\Http\Controllers\Admin\SmsPackageController;
use App\Http\Controllers\Admin\SmsPurchaseController as AdminSmsPurchaseController;
use App\Http\Controllers\Admin\SmsSettingsController;
use App\Http\Controllers\Admin\TenantController;
use App\Http\Controllers\EmailSettingsController;
use App\Http\Controllers\Auth\LoginController;
use App\Http\Controllers\Auth\RegisterController;
use App\Http\Controllers\BillController;
use App\Http\Controllers\ClientController;
use App\Http\Controllers\DashboardController;
use App\Http\Controllers\DocumentController;
use App\Http\Controllers\PaymentInController;
use App\Http\Controllers\PaymentOutController;
use App\Http\Controllers\PesapalWebhookController;
use App\Http\Controllers\ProductServiceController;
use App\Http\Controllers\SettingsController;
use App\Http\Controllers\SmsPurchaseController;
use App\Http\Controllers\UserController;
use Illuminate\Support\Facades\Route;

// Auth (Public)
Route::post('/auth/register', [RegisterController::class, 'register']);
Route::post('/auth/login', [LoginController::class, 'login']);

// Pesapal webhooks (public, no auth)
Route::match(['get', 'post'], '/pesapal/ipn', [PesapalWebhookController::class, 'ipn']);
Route::get('/pesapal/callback', [PesapalWebhookController::class, 'callback']);

// Auth (Authenticated, no tenant required)
Route::middleware(['auth:sanctum'])->group(function () {
    Route::post('/auth/logout', [LoginController::class, 'logout']);
    Route::get('/auth/me', [LoginController::class, 'me']);
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
});

// Tenant-scoped routes
Route::middleware(['auth:sanctum', 'tenant'])->group(function () {

    // Clients
    Route::apiResource('clients', ClientController::class);

    // Products & Services
    Route::apiResource('product-services', ProductServiceController::class);
    Route::get('/products', [ProductServiceController::class, 'products']);
    Route::get('/services', [ProductServiceController::class, 'services']);

    // Documents
    Route::apiResource('documents', DocumentController::class);
    Route::post('/documents/{document}/convert', [DocumentController::class, 'convert']);
    Route::get('/documents/{document}/pdf', [DocumentController::class, 'downloadPdf']);
    Route::post('/documents/{document}/send', [DocumentController::class, 'send']);

    // Payments In
    Route::apiResource('payments-in', PaymentInController::class)->only(['index', 'store', 'show']);

    // Bills (Statutory)
    Route::apiResource('bills', BillController::class);

    // Payments Out
    Route::apiResource('payments-out', PaymentOutController::class)->only(['index', 'store', 'show']);

    // Dashboard
    Route::get('/dashboard/summary', [DashboardController::class, 'summary']);

    // Users (Team)
    Route::apiResource('users', UserController::class)->except(['destroy', 'show']);
    Route::patch('/users/{user}/toggle-active', [UserController::class, 'toggleActive']);

    // Settings
    Route::put('/settings/company', [SettingsController::class, 'updateCompany']);
    Route::put('/settings/profile', [SettingsController::class, 'updateProfile']);

    // Email settings (tenant admin)
    Route::get('/settings/email', [EmailSettingsController::class, 'show']);
    Route::put('/settings/email', [EmailSettingsController::class, 'update']);
    Route::post('/settings/email/test', [EmailSettingsController::class, 'test']);

    // SMS (tenant)
    Route::get('/sms/packages', [SmsPurchaseController::class, 'packages']);
    Route::get('/sms/balance', [SmsPurchaseController::class, 'balance']);
    Route::post('/sms/checkout', [SmsPurchaseController::class, 'checkout']);
    Route::get('/sms/purchases/{smsPurchase}/status', [SmsPurchaseController::class, 'checkStatus']);
    Route::get('/sms/purchases', [SmsPurchaseController::class, 'history']);
});

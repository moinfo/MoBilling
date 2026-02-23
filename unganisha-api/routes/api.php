<?php

use App\Http\Controllers\Auth\LoginController;
use App\Http\Controllers\Auth\RegisterController;
use App\Http\Controllers\BillController;
use App\Http\Controllers\ClientController;
use App\Http\Controllers\DashboardController;
use App\Http\Controllers\DocumentController;
use App\Http\Controllers\PaymentInController;
use App\Http\Controllers\PaymentOutController;
use App\Http\Controllers\ProductServiceController;
use App\Http\Controllers\SettingsController;
use App\Http\Controllers\UserController;
use Illuminate\Support\Facades\Route;

// Auth (Public)
Route::post('/auth/register', [RegisterController::class, 'register']);
Route::post('/auth/login', [LoginController::class, 'login']);

// Protected Routes
Route::middleware(['auth:sanctum', 'tenant'])->group(function () {

    // Auth
    Route::post('/auth/logout', [LoginController::class, 'logout']);
    Route::get('/auth/me', [LoginController::class, 'me']);

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
});

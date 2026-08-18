<?php

namespace App\Http\Controllers;

use App\Models\License;
use App\Models\LicensePurchase;
use App\Models\SmsPurchase;
use App\Models\Tenant;
use App\Models\TenantSubscription;
use App\Services\PesapalService;
use App\Services\ResellerService;
use App\Services\SubscriptionService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

class PesapalWebhookController extends Controller
{
    public function ipn(Request $request): JsonResponse
    {
        $orderTrackingId = $request->input('OrderTrackingId');
        $orderMerchantReference = $request->input('OrderMerchantReference');
        $orderNotificationType = $request->input('OrderNotificationType');

        Log::info('Pesapal IPN received', [
            'order_tracking_id' => $orderTrackingId,
            'merchant_ref' => $orderMerchantReference,
            'notification_type' => $orderNotificationType,
        ]);

        if (!$orderTrackingId) {
            return response()->json([
                'orderNotificationType' => $orderNotificationType,
                'orderTrackingId' => $orderTrackingId,
                'orderMerchantReference' => $orderMerchantReference,
                'status' => 400,
            ], 400);
        }

        // Triple-lookup: try SmsPurchase, then TenantSubscription, then LicensePurchase
        $purchase = SmsPurchase::withoutGlobalScopes()
            ->where('order_tracking_id', $orderTrackingId)
            ->first();

        $subscription = null;
        if (!$purchase) {
            $subscription = TenantSubscription::withoutGlobalScopes()
                ->where('order_tracking_id', $orderTrackingId)
                ->first();
        }

        $licensePurchase = null;
        if (!$purchase && !$subscription) {
            $licensePurchase = LicensePurchase::where('order_tracking_id', $orderTrackingId)->first();
        }

        if (!$purchase && !$subscription && !$licensePurchase) {
            Log::warning('Pesapal IPN: no matching record', ['order_tracking_id' => $orderTrackingId]);
            return response()->json([
                'orderNotificationType' => $orderNotificationType,
                'orderTrackingId' => $orderTrackingId,
                'orderMerchantReference' => $orderMerchantReference,
                'status' => 404,
            ]);
        }

        // Verify server-side with Pesapal
        try {
            $pesapal = new PesapalService();
            $status = $pesapal->getTransactionStatus($orderTrackingId);
        } catch (\Throwable $e) {
            Log::error('Pesapal IPN: status check failed', [
                'order_tracking_id' => $orderTrackingId,
                'error' => $e->getMessage(),
            ]);
            return response()->json([
                'orderNotificationType' => $orderNotificationType,
                'orderTrackingId' => $orderTrackingId,
                'orderMerchantReference' => $orderMerchantReference,
                'status' => 500,
            ], 500);
        }

        $statusCode = $status['status_code'] ?? null;
        $description = $status['payment_status_description'] ?? '';

        if ($purchase) {
            $purchase->update([
                'payment_status_description' => $description,
                'confirmation_code' => $status['confirmation_code'] ?? null,
                'payment_method_used' => $status['payment_method'] ?? null,
            ]);

            Log::info('Pesapal IPN: SMS purchase status', [
                'purchase_id' => $purchase->id,
                'status_code' => $statusCode,
            ]);

            if ($statusCode === 1 && $description === 'Completed') {
                $this->processSmsCompleted($purchase);
            } elseif (in_array($statusCode, [0, 2, 3])) {
                $this->processSmsFailed($purchase, $description);
            }
        } elseif ($licensePurchase) {
            $licensePurchase->update([
                'payment_status_description' => $description,
                'confirmation_code' => $status['confirmation_code'] ?? null,
                'payment_method_used' => $status['payment_method'] ?? null,
                'gateway_response' => $status,
            ]);

            Log::info('Pesapal IPN: license purchase status', [
                'purchase_id' => $licensePurchase->id,
                'status_code' => $statusCode,
            ]);

            if ($statusCode === 1 && $description === 'Completed') {
                $this->processLicensePurchaseCompleted($licensePurchase);
            } elseif (in_array($statusCode, [0, 2, 3])) {
                $this->processLicensePurchaseFailed($licensePurchase);
            }
        } else {
            $subscription->update([
                'payment_status_description' => $description,
                'confirmation_code' => $status['confirmation_code'] ?? null,
                'payment_method_used' => $status['payment_method'] ?? null,
                'gateway_response' => $status,
            ]);

            Log::info('Pesapal IPN: subscription status', [
                'subscription_id' => $subscription->id,
                'status_code' => $statusCode,
            ]);

            $subService = new SubscriptionService();

            if ($statusCode === 1 && $description === 'Completed') {
                $subService->processPaymentCompleted($subscription);
            } elseif (in_array($statusCode, [0, 2, 3])) {
                $subService->processPaymentFailed($subscription);
            }
        }

        return response()->json([
            'orderNotificationType' => $orderNotificationType,
            'orderTrackingId' => $orderTrackingId,
            'orderMerchantReference' => $orderMerchantReference,
            'status' => 200,
        ]);
    }

    public function callback(Request $request): JsonResponse
    {
        $orderTrackingId = $request->input('OrderTrackingId');

        $type = null;
        $record = null;
        $status = 'unknown';

        if ($orderTrackingId) {
            // Try SMS purchase first
            $record = SmsPurchase::withoutGlobalScopes()
                ->where('order_tracking_id', $orderTrackingId)
                ->first();

            if ($record) {
                $type = 'sms_purchase';
                $status = $record->status;
            } else {
                // Try subscription
                $record = TenantSubscription::withoutGlobalScopes()
                    ->where('order_tracking_id', $orderTrackingId)
                    ->first();

                if ($record) {
                    $type = 'subscription';
                    $status = $record->status;
                } else {
                    // Try license purchase
                    $record = LicensePurchase::where('order_tracking_id', $orderTrackingId)->first();

                    if ($record) {
                        $type = 'license_purchase';
                        $status = $record->status;
                    }
                }
            }

            if ($record && $status === 'pending') {
                try {
                    $pesapal = new PesapalService();
                    $result = $pesapal->getTransactionStatus($orderTrackingId);
                    $statusCode = $result['status_code'] ?? null;

                    if ($statusCode === 1) {
                        $status = 'completed';
                    } elseif (in_array($statusCode, [0, 2, 3])) {
                        $status = 'failed';
                    }
                } catch (\Throwable $e) {
                    Log::error('Pesapal callback: status check failed', ['error' => $e->getMessage()]);
                }
            }
        }

        $license = null;
        if ($type === 'license_purchase' && $status === 'completed' && $record->license_id) {
            $license = License::find($record->license_id);
        }

        return response()->json([
            'type' => $type,
            'status' => $status,
            'record_id' => $record?->id,
            'order_tracking_id' => $orderTrackingId,
            'license_key' => $license?->license_key,
            'license_expires_at' => $license?->expires_at?->toDateString(),
        ]);
    }

    private function processSmsCompleted(SmsPurchase $purchase): void
    {
        if ($purchase->status !== 'pending') {
            Log::info('Pesapal: purchase already processed, skipping', ['purchase_id' => $purchase->id]);
            return;
        }

        $tenant = Tenant::find($purchase->tenant_id);

        if (!$tenant || !$tenant->gateway_email) {
            Log::error('Pesapal: cannot recharge — tenant missing or no gateway email', [
                'purchase_id' => $purchase->id,
                'tenant_id' => $purchase->tenant_id,
            ]);

            $purchase->update(['status' => 'failed']);
            return;
        }

        try {
            $reseller = new ResellerService();
            $gatewayResponse = $reseller->recharge($tenant->gateway_email, $purchase->sms_quantity);
        } catch (\Throwable $e) {
            Log::error('Pesapal: gateway recharge failed', [
                'purchase_id' => $purchase->id,
                'error' => $e->getMessage(),
            ]);

            $purchase->update(['status' => 'failed']);
            return;
        }

        $datePrefix = 'SMS-REC-' . now()->format('Ymd') . '-';
        $count = SmsPurchase::withoutGlobalScopes()
            ->where('receipt_number', 'LIKE', $datePrefix . '%')
            ->count();
        $receiptNumber = $datePrefix . str_pad($count + 1, 4, '0', STR_PAD_LEFT);

        $purchase->update([
            'status' => 'completed',
            'receipt_number' => $receiptNumber,
            'gateway_response' => $gatewayResponse,
            'completed_at' => now(),
        ]);

        Log::info('Pesapal: purchase auto-completed and recharged', [
            'purchase_id' => $purchase->id,
            'tenant' => $tenant->name,
            'quantity' => $purchase->sms_quantity,
        ]);
    }

    private function processSmsFailed(SmsPurchase $purchase, string $statusDescription): void
    {
        if ($purchase->status !== 'pending') {
            return;
        }

        $purchase->update(['status' => 'failed']);

        Log::info('Pesapal: payment failed/reversed', [
            'purchase_id' => $purchase->id,
            'status' => $statusDescription,
        ]);
    }

    private function processLicensePurchaseCompleted(LicensePurchase $purchase): void
    {
        if ($purchase->status !== 'pending') {
            Log::info('Pesapal: license purchase already processed, skipping', ['purchase_id' => $purchase->id]);
            return;
        }

        $license = License::create([
            'license_key' => License::generateKey(),
            'customer_name' => $purchase->customer_name,
            'customer_email' => $purchase->customer_email,
            'product' => $purchase->product,
            'billing_period' => $purchase->billing_period,
            'starts_at' => now()->toDateString(),
            'expires_at' => License::calculateExpiry(now()->toDateString(), $purchase->billing_period),
            'status' => 'active',
            'amount_paid' => $purchase->amount,
            'notes' => "Auto-issued via Pesapal purchase #{$purchase->id}",
        ]);

        $purchase->update([
            'status' => 'completed',
            'license_id' => $license->id,
            'completed_at' => now(),
        ]);

        Log::info('Pesapal: license auto-issued', [
            'purchase_id' => $purchase->id,
            'license_id' => $license->id,
            'license_key' => $license->license_key,
        ]);
    }

    private function processLicensePurchaseFailed(LicensePurchase $purchase): void
    {
        if ($purchase->status !== 'pending') {
            return;
        }

        $purchase->update(['status' => 'failed']);

        Log::info('Pesapal: license purchase failed/reversed', ['purchase_id' => $purchase->id]);
    }
}

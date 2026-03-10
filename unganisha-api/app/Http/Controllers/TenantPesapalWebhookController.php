<?php

namespace App\Http\Controllers;

use App\Models\Document;
use App\Models\PaymentIn;
use App\Models\PesapalInvoicePayment;
use App\Services\TenantPesapalService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

class TenantPesapalWebhookController extends Controller
{
    /**
     * IPN callback from Pesapal for tenant invoice payments.
     */
    public function ipn(Request $request)
    {
        $orderTrackingId = $request->input('OrderTrackingId');
        $orderMerchantReference = $request->input('OrderMerchantReference');

        Log::info('Tenant Pesapal IPN received', [
            'order_tracking_id' => $orderTrackingId,
            'merchant_reference' => $orderMerchantReference,
        ]);

        if (!$orderTrackingId) {
            return response()->json(['status' => 'error', 'message' => 'Missing OrderTrackingId'], 400);
        }

        // Find the payment record
        $payment = PesapalInvoicePayment::where('order_tracking_id', $orderTrackingId)
            ->orWhere('merchant_reference', $orderMerchantReference)
            ->first();

        if (!$payment) {
            Log::warning('Tenant Pesapal IPN: payment not found', compact('orderTrackingId', 'orderMerchantReference'));
            return response()->json(['status' => 'error', 'message' => 'Payment not found'], 404);
        }

        // Already processed
        if ($payment->status === 'completed') {
            return response()->json(['status' => 'ok']);
        }

        $tenant = $payment->tenant;
        if (!$tenant || !$tenant->pesapal_consumer_key) {
            Log::error('Tenant Pesapal IPN: tenant credentials missing', ['payment_id' => $payment->id]);
            return response()->json(['status' => 'error'], 500);
        }

        // Verify with Pesapal
        try {
            $pesapal = new TenantPesapalService($tenant);
            $status = $pesapal->getTransactionStatus($orderTrackingId);
        } catch (\Throwable $e) {
            Log::error('Tenant Pesapal IPN: status check failed', [
                'payment_id' => $payment->id,
                'error' => $e->getMessage(),
            ]);
            return response()->json(['status' => 'error'], 500);
        }

        $statusCode = $status['status_code'] ?? null;
        $description = $status['payment_status_description'] ?? null;

        Log::info('Tenant Pesapal IPN: transaction status', [
            'payment_id' => $payment->id,
            'status_code' => $statusCode,
            'description' => $description,
        ]);

        $payment->update([
            'payment_status_description' => $description,
            'payment_method_used' => $status['payment_method'] ?? null,
            'confirmation_code' => $status['confirmation_code'] ?? null,
            'gateway_response' => $status,
        ]);

        // Status code 1 + "Completed" = success
        if ($statusCode == 1 && strtolower($description ?? '') === 'completed') {
            $this->processCompleted($payment);
        } elseif (in_array($statusCode, [2, 3])) {
            $payment->update(['status' => 'failed']);
        }

        return response()->json(['status' => 'ok']);
    }

    /**
     * Record the payment in payments_in and update invoice status.
     */
    private function processCompleted(PesapalInvoicePayment $payment): void
    {
        if ($payment->status === 'completed') {
            return;
        }

        $payment->update([
            'status' => 'completed',
            'completed_at' => now(),
        ]);

        $doc = $payment->document;
        if (!$doc) {
            return;
        }

        // Create payment record
        PaymentIn::create([
            'tenant_id' => $payment->tenant_id,
            'document_id' => $payment->document_id,
            'amount' => $payment->amount,
            'payment_date' => now()->toDateString(),
            'payment_method' => 'pesapal',
            'reference' => $payment->confirmation_code ?? $payment->order_tracking_id,
            'notes' => "Pesapal payment ({$payment->payment_method_used})",
        ]);

        // Update invoice status
        $doc->refresh();
        $balance = (float) $doc->balance_due;

        if ($balance <= 0) {
            $doc->update(['status' => 'paid']);
        } elseif ($balance < (float) $doc->total) {
            $doc->update(['status' => 'partial']);
        }

        Log::info('Tenant Pesapal: invoice payment completed', [
            'document_id' => $doc->id,
            'amount' => $payment->amount,
            'new_status' => $doc->status,
        ]);
    }
}

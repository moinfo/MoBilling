<?php

namespace App\Http\Controllers;

use App\Jobs\Wifi\ProvisionWifiVoucherJob;
use App\Models\Document;
use App\Models\PaymentIn;
use App\Models\PesapalInvoicePayment;
use App\Models\WifiVoucherPurchase;
use App\Services\SubscriptionActivationService;
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
            // Not an invoice payment — maybe a WiFi voucher sale instead
            // (a separate, no-Document/no-Client walk-in purchase).
            $voucherPurchase = WifiVoucherPurchase::where('order_tracking_id', $orderTrackingId)->first();
            if ($voucherPurchase) {
                return $this->handleWifiVoucherIpn($voucherPurchase);
            }

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
     * A completed online payment that the invoice can no longer absorb
     * (already paid / cancelled, or overpaying): credit the client wallet and
     * tell staff. Falls back to a staff alert alone when no client is linked.
     */
    private function handleExcess(PesapalInvoicePayment $payment, Document $doc, float $excess, bool $whole): void
    {
        $credited = false;
        try {
            $doc->loadMissing('client');
            if ($doc->client) {
                app(\App\Services\CreditService::class)->adjust(
                    $doc->client, $excess, 'deposit',
                    "Pesapal payment received after {$doc->document_number} was already settled (ref "
                        . ($payment->confirmation_code ?? $payment->order_tracking_id) . ')',
                    $doc->id,
                );
                $credited = true;
            }
        } catch (\Throwable $e) {
            Log::error('Tenant Pesapal: excess credit failed', ['payment_id' => $payment->id, 'error' => $e->getMessage()]);
        }

        Log::warning('Tenant Pesapal: payment on already-settled invoice', [
            'payment_id' => $payment->id, 'document_id' => $doc->id,
            'excess' => $excess, 'credited' => $credited, 'whole_payment' => $whole,
        ]);

        try {
            $staff = \App\Models\User::withPermission($doc->tenant_id, 'payments_in.read');
            if ($staff->isNotEmpty()) {
                \Illuminate\Support\Facades\Notification::send($staff, new \App\Notifications\PaymentExcessNotification($doc, $excess, $credited));
            }
        } catch (\Throwable $e) {
            Log::warning('Tenant Pesapal: excess staff notification failed', ['error' => $e->getMessage()]);
        }
    }

    /**
     * Record the payment in payments_in and update invoice status.
     */
    private function processCompleted(PesapalInvoicePayment $payment): void
    {
        // Atomic claim: only one concurrent IPN delivery may flip the row to
        // completed, so a duplicate/parallel callback can never book twice.
        $claimed = PesapalInvoicePayment::where('id', $payment->id)
            ->where('status', '!=', 'completed')
            ->update(['status' => 'completed', 'completed_at' => now()]);
        if (!$claimed) {
            return;
        }
        $payment->refresh();

        $doc = $payment->document;
        if (!$doc) {
            return;
        }

        // Double-booking guard: the invoice may have been paid another way
        // (cash, another link, wallet) or cancelled while this link was open.
        // Only book what the invoice can still absorb; the rest becomes
        // client credit (never silently lost, never a second full PaymentIn).
        $doc->refresh();
        $dueNow = ($doc->status === 'cancelled') ? 0.0 : max(0.0, round((float) $doc->balance_due, 2));
        $paidAmount = round((float) $payment->amount, 2);
        $bookAmount = round(min($paidAmount, $dueNow), 2);
        $excess = round($paidAmount - $bookAmount, 2);

        if ($excess > 0) {
            $this->handleExcess($payment, $doc, $excess, $bookAmount <= 0);
        }
        if ($bookAmount <= 0) {
            return;
        }

        // Create payment record
        $paymentIn = PaymentIn::create([
            'tenant_id' => $payment->tenant_id,
            'document_id' => $payment->document_id,
            'amount' => $bookAmount,
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
            // Manual payments (PaymentInController) and wallet credit
            // (CreditService) both flip a pending ClientSubscription to
            // active on payment — this was the one path that didn't, so an
            // order paid online via Pesapal stayed "pending" forever even
            // though hosting/domain provisioning (a separate trigger) ran fine.
            app(SubscriptionActivationService::class)->activateFor($doc);
        } elseif ($balance < (float) $doc->total) {
            $doc->update(['status' => 'partial']);
        }

        // Confirm the payment to the client (email / SMS / WhatsApp per tenant switches)
        try {
            $doc->loadMissing('client');
            if ($doc->client && ($doc->client->email || $doc->client->phone)) {
                $doc->client->notify(new \App\Notifications\PaymentReceiptNotification($paymentIn, $doc));
            }
        } catch (\Throwable $e) {
            Log::warning('Tenant Pesapal: receipt notification failed', ['error' => $e->getMessage()]);
        }

        // No staff member did anything here — an online gateway payment
        // landing with nobody watching is exactly the case worth alerting on.
        try {
            $staff = \App\Models\User::withPermission($doc->tenant_id, 'payments_in.read');
            if ($staff->isNotEmpty()) {
                \Illuminate\Support\Facades\Notification::send(
                    $staff,
                    new \App\Notifications\PaymentReceivedNotification($paymentIn, $doc),
                );
            }
        } catch (\Throwable $e) {
            Log::warning('Tenant Pesapal: staff payment notification failed', ['error' => $e->getMessage()]);
        }

        Log::info('Tenant Pesapal: invoice payment completed', [
            'document_id' => $doc->id,
            'amount' => $payment->amount,
            'new_status' => $doc->status,
        ]);
    }

    /**
     * IPN handling for a WifiVoucherPurchase — same verify-then-complete
     * shape as the invoice-payment path above, but there's no Document,
     * no Client, and completion means provisioning a hotspot user rather
     * than recording a PaymentIn.
     */
    private function handleWifiVoucherIpn(WifiVoucherPurchase $purchase)
    {
        if ($purchase->status !== 'pending') {
            return response()->json(['status' => 'ok']);
        }

        $tenant = $purchase->tenant()->withoutGlobalScopes()->first();
        if (!$tenant || !$tenant->pesapal_consumer_key) {
            Log::error('Tenant Pesapal IPN: tenant credentials missing for wifi voucher', ['purchase_id' => $purchase->id]);
            return response()->json(['status' => 'error'], 500);
        }

        try {
            $pesapal = new TenantPesapalService($tenant);
            $status = $pesapal->getTransactionStatus($purchase->order_tracking_id);
        } catch (\Throwable $e) {
            Log::error('Tenant Pesapal IPN: wifi voucher status check failed', [
                'purchase_id' => $purchase->id,
                'error'       => $e->getMessage(),
            ]);
            return response()->json(['status' => 'error'], 500);
        }

        $statusCode = $status['status_code'] ?? null;
        $description = $status['payment_status_description'] ?? null;

        $purchase->update([
            'payment_status_description' => $description,
            'payment_method_used'        => $status['payment_method'] ?? null,
            'confirmation_code'          => $status['confirmation_code'] ?? null,
            'gateway_response'           => $status,
        ]);

        if ($statusCode == 1 && strtolower($description ?? '') === 'completed') {
            $this->processWifiVoucherCompleted($purchase);
        } elseif (in_array($statusCode, [2, 3])) {
            $purchase->update(['status' => 'failed']);
        }

        return response()->json(['status' => 'ok']);
    }

    private function processWifiVoucherCompleted(WifiVoucherPurchase $purchase): void
    {
        if ($purchase->status !== 'pending') {
            return;
        }

        $purchase->update(['status' => 'completed', 'completed_at' => now()]);

        ProvisionWifiVoucherJob::dispatch($purchase);

        Log::info('Tenant Pesapal: wifi voucher purchase completed', [
            'purchase_id' => $purchase->id,
            'amount'      => $purchase->amount,
        ]);
    }
}

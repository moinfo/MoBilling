<?php

namespace App\Http\Controllers;

use App\Models\Document;
use App\Models\PaymentIn;
use App\Models\PesapalInvoicePayment;
use App\Models\Tenant;
use App\Services\TenantPesapalService;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

class InvoicePaymentController extends Controller
{
    /**
     * Public: Get invoice details for payment page (no auth required).
     */
    public function show(string $documentId)
    {
        $doc = Document::with(['client:id,name,email,phone', 'items', 'tenant:id,name,currency,logo_path,pesapal_enabled,bank_name,bank_account_name,bank_account_number,bank_branch,payment_instructions'])
            ->findOrFail($documentId);

        if ($doc->type !== 'invoice') {
            abort(404, 'Document is not an invoice.');
        }

        return response()->json([
            'invoice' => [
                'id' => $doc->id,
                'document_number' => $doc->document_number,
                'date' => $doc->date?->format('Y-m-d'),
                'due_date' => $doc->due_date?->format('Y-m-d'),
                'total' => (float) $doc->total,
                'paid_amount' => (float) $doc->paid_amount,
                'balance_due' => (float) $doc->balance_due,
                'status' => $doc->status,
                'notes' => $doc->notes,
                'items' => $doc->items->map(fn ($item) => [
                    'description' => $item->description,
                    'quantity' => $item->quantity,
                    'unit_price' => (float) $item->unit_price,
                    'amount' => (float) $item->amount,
                ]),
                'client' => [
                    'name' => $doc->client?->name,
                    'email' => $doc->client?->email,
                ],
            ],
            'tenant' => [
                'name' => $doc->tenant?->name,
                'currency' => $doc->tenant?->currency ?? 'TZS',
                'logo_url' => $doc->tenant?->logo_url,
                'pesapal_enabled' => (bool) $doc->tenant?->pesapal_enabled,
                'bank_name' => $doc->tenant?->bank_name,
                'bank_account_name' => $doc->tenant?->bank_account_name,
                'bank_account_number' => $doc->tenant?->bank_account_number,
                'bank_branch' => $doc->tenant?->bank_branch,
                'payment_instructions' => $doc->tenant?->payment_instructions,
            ],
        ]);
    }

    /**
     * Public: Initiate Pesapal payment for an invoice.
     */
    public function checkout(Request $request, string $documentId)
    {
        $request->validate([
            'amount' => 'nullable|numeric|min:1',
        ]);

        $doc = Document::with('client', 'tenant')->findOrFail($documentId);

        if ($doc->type !== 'invoice') {
            abort(400, 'Not an invoice.');
        }

        if ($doc->status === 'paid') {
            return response()->json(['message' => 'Invoice is already paid.'], 400);
        }

        $tenant = $doc->tenant;
        if (!$tenant || !$tenant->pesapal_enabled || !$tenant->pesapal_consumer_key) {
            return response()->json(['message' => 'Online payment is not available for this invoice.'], 400);
        }

        $balanceDue = (float) $doc->balance_due;
        $amount = $request->amount ? min((float) $request->amount, $balanceDue) : $balanceDue;

        if ($amount <= 0) {
            return response()->json(['message' => 'No balance due.'], 400);
        }

        $merchantRef = 'INV-' . $doc->id . '-' . Str::random(6);

        // Submit to Pesapal
        $pesapal = new TenantPesapalService($tenant);

        // Determine callback URL based on context (portal vs public)
        $isPortal = $request->user() !== null;
        $frontendUrl = config('app.frontend_url', 'https://mobilling.co.tz');
        $callbackUrl = $isPortal
            ? "{$frontendUrl}/portal/invoices"
            : "{$frontendUrl}/pay/{$doc->id}";

        $result = $pesapal->submitOrder(
            $merchantRef,
            $amount,
            "Payment for {$doc->document_number}",
            [
                'email' => $doc->client?->email ?? '',
                'phone' => $doc->client?->phone ?? '',
                'first_name' => $doc->client?->name ?? '',
                'last_name' => '',
            ],
            $callbackUrl
        );

        // Track the payment
        $payment = PesapalInvoicePayment::create([
            'tenant_id' => $tenant->id,
            'document_id' => $doc->id,
            'merchant_reference' => $merchantRef,
            'order_tracking_id' => $result['order_tracking_id'] ?? null,
            'pesapal_redirect_url' => $result['redirect_url'] ?? null,
            'amount' => $amount,
            'currency' => $tenant->currency ?? 'TZS',
            'status' => 'pending',
        ]);

        return response()->json([
            'payment_id' => $payment->id,
            'redirect_url' => $result['redirect_url'] ?? null,
            'order_tracking_id' => $result['order_tracking_id'] ?? null,
        ]);
    }

    /**
     * Public: Check payment status.
     */
    public function status(string $documentId, string $paymentId)
    {
        $payment = PesapalInvoicePayment::where('document_id', $documentId)
            ->findOrFail($paymentId);

        return response()->json([
            'status' => $payment->status,
            'amount' => (float) $payment->amount,
            'confirmation_code' => $payment->confirmation_code,
            'payment_method' => $payment->payment_method_used,
            'completed_at' => $payment->completed_at,
        ]);
    }

    /**
     * Check payment status by Pesapal OrderTrackingId.
     */
    public function statusByTracking(Request $request)
    {
        $trackingId = $request->query('OrderTrackingId');
        if (!$trackingId) {
            return response()->json(['message' => 'Missing OrderTrackingId'], 400);
        }

        $payment = PesapalInvoicePayment::where('order_tracking_id', $trackingId)->first();
        if (!$payment) {
            return response()->json(['message' => 'Payment not found'], 404);
        }

        return response()->json([
            'status' => $payment->status,
            'amount' => (float) $payment->amount,
            'confirmation_code' => $payment->confirmation_code,
            'payment_method' => $payment->payment_method_used,
            'completed_at' => $payment->completed_at,
            'document_id' => $payment->document_id,
        ]);
    }
}

<?php

namespace App\Http\Controllers;

use App\Http\Requests\StorePaymentInRequest;
use App\Http\Resources\PaymentInResource;
use App\Models\ClientSubscription;
use App\Models\Document;
use App\Models\PaymentIn;
use App\Models\RecurringInvoiceLog;
use App\Notifications\PaymentReceiptNotification;
use Illuminate\Http\Request;

class PaymentInController extends Controller
{
    public function index(Request $request)
    {
        $query = PaymentIn::with('document.client');

        if ($request->has('document_id')) {
            $query->where('document_id', $request->document_id);
        }

        return PaymentInResource::collection(
            $query->orderByDesc('payment_date')->paginate($request->per_page ?? 20)
        );
    }

    public function store(StorePaymentInRequest $request)
    {
        $payment = PaymentIn::create($request->validated());

        // Update document status
        $document = Document::find($request->document_id);
        $totalPaid = $document->payments()->sum('amount');

        if ($totalPaid >= $document->total) {
            $document->update(['status' => 'paid']);
            $this->activateLinkedSubscriptions($document);
        } else {
            $document->update(['status' => 'partial']);
        }

        // Send payment receipt email to client
        $document->load('client');
        if ($document->client?->email) {
            $document->client->notify(new PaymentReceiptNotification($payment, $document));
        }

        return new PaymentInResource($payment);
    }

    public function show(PaymentIn $payments_in)
    {
        return new PaymentInResource($payments_in->load('document'));
    }

    public function update(StorePaymentInRequest $request, PaymentIn $payments_in)
    {
        $payments_in->update($request->validated());

        $this->recalcDocumentStatus($payments_in->document_id);

        return new PaymentInResource($payments_in);
    }

    public function destroy(PaymentIn $payments_in)
    {
        $documentId = $payments_in->document_id;
        $payments_in->delete();

        $this->recalcDocumentStatus($documentId);

        return response()->json(['message' => 'Payment deleted']);
    }

    public function resendReceipt(PaymentIn $payments_in)
    {
        $payments_in->load('document.client');
        $client = $payments_in->document?->client;

        if (!$client?->email) {
            return response()->json(['message' => 'Client has no email address'], 422);
        }

        $client->notify(new PaymentReceiptNotification($payments_in, $payments_in->document));

        return response()->json(['message' => 'Receipt email sent']);
    }

    private function recalcDocumentStatus(string $documentId): void
    {
        $document = Document::find($documentId);
        if (!$document) return;

        $totalPaid = $document->payments()->sum('amount');

        if ($totalPaid >= $document->total) {
            $document->update(['status' => 'paid']);
            $this->activateLinkedSubscriptions($document);
        } elseif ($totalPaid > 0) {
            $document->update(['status' => 'partial']);
        } else {
            $document->update(['status' => 'sent']);
        }
    }

    /**
     * When an invoice is paid, activate any pending subscriptions linked to it.
     */
    private function activateLinkedSubscriptions(Document $document): void
    {
        $productIds = RecurringInvoiceLog::where('document_id', $document->id)
            ->pluck('product_service_id');

        if ($productIds->isEmpty()) {
            return;
        }

        ClientSubscription::where('client_id', $document->client_id)
            ->whereIn('product_service_id', $productIds)
            ->where('status', 'pending')
            ->update(['status' => 'active']);
    }
}

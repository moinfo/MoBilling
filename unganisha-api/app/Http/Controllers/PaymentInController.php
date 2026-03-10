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

        if ($request->filled('search')) {
            $search = $request->search;
            $query->where(function ($q) use ($search) {
                $q->where('reference', 'LIKE', "%{$search}%")
                  ->orWhereHas('document', fn ($dq) => $dq
                      ->where('document_number', 'LIKE', "%{$search}%")
                      ->orWhereHas('client', fn ($cq) => $cq->where('name', 'LIKE', "%{$search}%"))
                  );
            });
        }

        if ($request->filled('date_from')) {
            $query->where('payment_date', '>=', $request->date_from);
        }

        if ($request->filled('date_to')) {
            $query->where('payment_date', '<=', $request->date_to);
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

        // Send payment receipt email to client (refresh to get updated status)
        $document->refresh();
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
     * When an invoice is paid, activate any linked subscriptions
     * and advance their expire_date to the next billing period.
     */
    private function activateLinkedSubscriptions(Document $document): void
    {
        $logs = RecurringInvoiceLog::where('document_id', $document->id)->get();

        if ($logs->isEmpty()) {
            return;
        }

        // Collect specific subscription IDs (new logs) and fallback product IDs (old logs)
        $subscriptionIds = $logs->pluck('client_subscription_id')->filter()->unique()->values();
        $fallbackProductIds = $logs->whereNull('client_subscription_id')->pluck('product_service_id')->unique()->values();

        $subscriptions = ClientSubscription::with('productService')
            ->where('client_id', $document->client_id)
            ->whereIn('status', ['pending', 'suspended', 'active'])
            ->where(function ($q) use ($subscriptionIds, $fallbackProductIds) {
                if ($subscriptionIds->isNotEmpty()) {
                    $q->whereIn('id', $subscriptionIds);
                }
                if ($fallbackProductIds->isNotEmpty()) {
                    $q->orWhereIn('product_service_id', $fallbackProductIds);
                }
            })
            ->get();

        foreach ($subscriptions as $sub) {
            $baseDate = $sub->expire_date ?? $sub->start_date;
            $cycle = $sub->productService?->billing_cycle;

            $newExpireDate = match ($cycle) {
                'monthly' => $baseDate->copy()->addMonth(),
                'quarterly' => $baseDate->copy()->addMonths(3),
                'half_yearly' => $baseDate->copy()->addMonths(6),
                'yearly' => $baseDate->copy()->addYear(),
                default => $baseDate,
            };

            $sub->update([
                'status' => 'active',
                'expire_date' => $newExpireDate,
            ]);
        }
    }
}

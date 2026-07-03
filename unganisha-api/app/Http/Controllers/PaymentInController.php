<?php

namespace App\Http\Controllers;

use App\Http\Requests\StorePaymentInRequest;
use App\Http\Resources\PaymentInResource;
use App\Models\ClientSubscription;
use App\Models\Document;
use App\Models\PaymentIn;
use App\Models\RecurringInvoiceLog;
use App\Notifications\PaymentReceiptNotification;
use App\Services\PdfService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class PaymentInController extends Controller
{
    public function index(Request $request)
    {
        $query = PaymentIn::with(['document.client', 'client', 'receiver']);

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
        // Insert the payment and recompute the invoice status atomically.
        // lockForUpdate serialises concurrent payments on the same invoice so
        // the running total can't be computed against stale data.
        $payment = DB::transaction(function () use ($request) {
            $payment = PaymentIn::create(array_merge($request->validated(), [
                'received_by' => auth()->id(),
            ]));

            if ($request->document_id) {
                $document = Document::whereKey($request->document_id)->lockForUpdate()->first();
                if ($document) {
                    $totalPaid = $document->payments()->sum('amount');

                    if ($totalPaid >= $document->total) {
                        $document->update(['status' => 'paid']);
                        $this->activateLinkedSubscriptions($document);
                    } else {
                        $document->update(['status' => 'partial']);
                    }
                }
            }

            return $payment;
        });

        // Send the receipt email outside the transaction — network I/O should
        // not hold the row lock open.
        if ($request->document_id && $request->boolean('send_email', true)) {
            $document = Document::with('client')->find($request->document_id);
            if ($document?->client?->email) {
                $document->client->notify(new PaymentReceiptNotification($payment, $document));
            }
        }

        return new PaymentInResource($payment);
    }

    public function show(PaymentIn $payments_in)
    {
        return new PaymentInResource($payments_in->load('document'));
    }

    public function update(StorePaymentInRequest $request, PaymentIn $payments_in)
    {
        DB::transaction(function () use ($request, $payments_in) {
            $payments_in->update($request->validated());
            $this->recalcDocumentStatus($payments_in->document_id);
        });

        return new PaymentInResource($payments_in);
    }

    public function destroy(PaymentIn $payments_in)
    {
        DB::transaction(function () use ($payments_in) {
            $documentId = $payments_in->document_id;
            $payments_in->delete();
            $this->recalcDocumentStatus($documentId);
        });

        return response()->json(['message' => 'Payment deleted']);
    }

    public function downloadReceipt(PaymentIn $payments_in)
    {
        $payments_in->load('document.client', 'document.items', 'document.tenant');

        $pdf = app(PdfService::class)->generateReceipt($payments_in, $payments_in->document);
        $receiptNumber = 'RCT-' . $payments_in->payment_date->format('Ymd') . '-' . strtoupper(substr($payments_in->id, 0, 6));

        return $pdf->download("{$receiptNumber}.pdf");
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
        $document = Document::whereKey($documentId)->lockForUpdate()->first();
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

    private function activateLinkedSubscriptions(Document $document): void
    {
        app(\App\Services\SubscriptionActivationService::class)->activateFor($document);
    }
}

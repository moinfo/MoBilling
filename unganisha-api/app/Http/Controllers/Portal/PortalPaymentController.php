<?php

namespace App\Http\Controllers\Portal;

use App\Http\Controllers\Controller;
use App\Models\PaymentIn;
use App\Services\PdfService;
use Illuminate\Http\Request;

class PortalPaymentController extends Controller
{
    public function index(Request $request)
    {
        $clientId = $request->user()->client_id;

        $query = PaymentIn::whereHas('document', fn ($q) => $q->where('client_id', $clientId))
            ->with('document:id,document_number,type')
            ->orderByDesc('payment_date');

        if ($request->filled('search')) {
            $query->where(function ($q) use ($request) {
                $q->where('reference', 'like', "%{$request->search}%")
                  ->orWhereHas('document', fn ($dq) => $dq->where('document_number', 'like', "%{$request->search}%"));
            });
        }

        return response()->json($query->paginate($request->get('per_page', 20)));
    }

    public function downloadReceipt(Request $request, PaymentIn $payment)
    {
        $clientId = $request->user()->client_id;

        // Verify this payment belongs to the client
        $payment->load('document.client', 'document.items', 'document.tenant');
        if ($payment->document?->client_id !== $clientId) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $pdf = app(PdfService::class)->generateReceipt($payment, $payment->document);
        $receiptNumber = 'RCT-' . $payment->payment_date->format('Ymd') . '-' . strtoupper(substr($payment->id, 0, 6));

        return $pdf->download("{$receiptNumber}.pdf");
    }
}

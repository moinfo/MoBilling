<?php

namespace App\Http\Controllers;

use App\Http\Requests\StorePaymentInRequest;
use App\Http\Resources\PaymentInResource;
use App\Models\Document;
use App\Models\PaymentIn;
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
        } else {
            $document->update(['status' => 'partial']);
        }

        return new PaymentInResource($payment);
    }

    public function show(PaymentIn $payments_in)
    {
        return new PaymentInResource($payments_in->load('document'));
    }
}

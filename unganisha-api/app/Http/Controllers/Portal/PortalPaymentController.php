<?php

namespace App\Http\Controllers\Portal;

use App\Http\Controllers\Controller;
use App\Models\PaymentIn;
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
}

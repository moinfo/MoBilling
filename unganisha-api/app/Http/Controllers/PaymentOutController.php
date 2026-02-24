<?php

namespace App\Http\Controllers;

use App\Http\Requests\StorePaymentOutRequest;
use App\Http\Resources\PaymentOutResource;
use App\Models\Bill;
use App\Models\PaymentOut;
use Illuminate\Http\Request;

class PaymentOutController extends Controller
{
    public function index(Request $request)
    {
        $query = PaymentOut::with('bill');

        if ($request->has('bill_id')) {
            $query->where('bill_id', $request->bill_id);
        }

        return PaymentOutResource::collection(
            $query->orderByDesc('payment_date')->paginate($request->per_page ?? 20)
        );
    }

    public function store(StorePaymentOutRequest $request)
    {
        $payment = PaymentOut::create($request->validated());

        // Advance bill due date to next cycle (or deactivate if one-time)
        $bill = Bill::find($request->bill_id);
        if ($bill->cycle === 'once') {
            $bill->update(['is_active' => false]);
        } else {
            $bill->update(['due_date' => $bill->next_due_date]);
        }

        return new PaymentOutResource($payment->load('bill'));
    }

    public function show(PaymentOut $payments_out)
    {
        return new PaymentOutResource($payments_out->load('bill'));
    }
}

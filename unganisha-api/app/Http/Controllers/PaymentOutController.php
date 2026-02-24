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
        $data = $request->safe()->except('receipt');

        if ($request->hasFile('receipt')) {
            $data['receipt_path'] = $request->file('receipt')->store('receipts/payments-out', 'public');
        }

        $payment = PaymentOut::create($data);

        // Mark bill as paid if total payments cover the bill amount
        $bill = Bill::find($request->bill_id);
        $totalPaid = $bill->payments()->sum('amount');
        if ($totalPaid >= $bill->amount) {
            $bill->update(['paid_at' => now()]);

            // If linked to a statutory obligation, advance and generate next bill
            if ($bill->statutory_id) {
                $statutory = $bill->statutory;
                if ($statutory && $statutory->is_active) {
                    $advanced = $statutory->advanceDueDate();
                    if ($advanced) {
                        $statutory->generateBill();
                    }
                }
            }
        }

        return new PaymentOutResource($payment->load('bill'));
    }

    public function show(PaymentOut $payments_out)
    {
        return new PaymentOutResource($payments_out->load('bill'));
    }

    public function update(Request $request, PaymentOut $payments_out)
    {
        $validated = $request->validate([
            'amount' => 'sometimes|numeric|min:0.01',
            'payment_date' => 'sometimes|date',
            'payment_method' => 'sometimes|in:cash,bank,mpesa,card,other',
            'control_number' => 'nullable|string|max:255',
            'reference' => 'nullable|string|max:255',
            'notes' => 'nullable|string|max:1000',
        ]);

        $payments_out->update($validated);

        // Recalculate bill paid status
        $bill = $payments_out->bill;
        $totalPaid = $bill->payments()->sum('amount');
        $bill->update(['paid_at' => $totalPaid >= $bill->amount ? ($bill->paid_at ?? now()) : null]);

        return new PaymentOutResource($payments_out->load('bill'));
    }

    public function destroy(PaymentOut $payments_out)
    {
        $bill = $payments_out->bill;
        $payments_out->delete();

        // Recalculate bill paid status
        $totalPaid = $bill->payments()->sum('amount');
        $bill->update(['paid_at' => $totalPaid >= $bill->amount ? $bill->paid_at : null]);

        return response()->json(['message' => 'Payment deleted']);
    }
}

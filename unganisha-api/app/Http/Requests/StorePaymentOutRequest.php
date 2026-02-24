<?php

namespace App\Http\Requests;

use App\Models\Bill;
use Illuminate\Foundation\Http\FormRequest;

class StorePaymentOutRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'bill_id' => 'required|uuid|exists:bills,id',
            'amount' => 'required|numeric|min:0.01',
            'payment_date' => 'required|date',
            'payment_method' => 'required|in:cash,bank,mpesa,card,other',
            'control_number' => 'nullable|string|max:255',
            'reference' => 'nullable|string|max:255',
            'notes' => 'nullable|string|max:1000',
            'receipt' => 'nullable|file|mimes:pdf,jpg,jpeg,png|max:5120',
        ];
    }

    public function withValidator($validator): void
    {
        $validator->after(function ($validator) {
            if ($this->bill_id && $this->amount) {
                $bill = Bill::find($this->bill_id);
                if ($bill) {
                    if ($bill->paid_at) {
                        $validator->errors()->add('bill_id', 'This bill is already fully paid.');
                        return;
                    }
                    $totalPaid = $bill->payments()->sum('amount');
                    $remaining = $bill->amount - $totalPaid;
                    if ($this->amount > $remaining) {
                        $validator->errors()->add('amount', "Amount exceeds remaining balance ({$remaining}).");
                    }
                }
            }
        });
    }
}

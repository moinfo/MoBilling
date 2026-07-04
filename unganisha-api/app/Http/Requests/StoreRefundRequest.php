<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StoreRefundRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'amount'    => 'required|numeric|min:0.01',
            'method'    => ['required', Rule::in(['wallet', 'cash', 'bank', 'mpesa', 'pesapal', 'other'])],
            'reference' => 'nullable|string|max:255',
            'reason'    => 'nullable|string|max:1000',
        ];
    }
}

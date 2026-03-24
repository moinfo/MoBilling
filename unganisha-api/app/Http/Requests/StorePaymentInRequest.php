<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StorePaymentInRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        $methods = $this->allowedPaymentMethods();

        return [
            'client_id' => 'required|uuid|exists:clients,id',
            'document_id' => 'nullable|uuid|exists:documents,id',
            'amount' => 'required|numeric|min:0.01',
            'payment_date' => 'required|date',
            'payment_method' => ['required', 'string', Rule::in($methods)],
            'reference' => 'nullable|string|max:255',
            'notes' => 'nullable|string|max:1000',
        ];
    }

    private function allowedPaymentMethods(): array
    {
        $tenant = auth()->user()?->tenant;
        if ($tenant && !empty($tenant->payment_methods)) {
            return collect($tenant->payment_methods)->pluck('value')->all();
        }

        return ['cash', 'bank', 'mpesa', 'card', 'other'];
    }
}
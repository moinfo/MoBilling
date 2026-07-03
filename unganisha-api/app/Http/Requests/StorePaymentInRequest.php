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
        $methods  = $this->allowedPaymentMethods();
        $tenantId = auth()->user()?->tenant_id;

        return [
            // Scope existence checks to the current tenant — the raw `exists` rule
            // bypasses the BelongsToTenant global scope, so without this a foreign
            // client/document id would validate.
            'client_id' => ['required', 'uuid', Rule::exists('clients', 'id')->where('tenant_id', $tenantId)],
            'document_id' => ['nullable', 'uuid', Rule::exists('documents', 'id')->where('tenant_id', $tenantId)],
            'amount' => 'required|numeric|min:0.01',
            'payment_date' => 'required|date|before_or_equal:today',
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
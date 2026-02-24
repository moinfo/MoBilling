<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class StoreClientSubscriptionRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'client_id' => 'required|uuid|exists:clients,id',
            'product_service_id' => 'required|uuid|exists:product_services,id',
            'label' => 'nullable|string|max:255',
            'quantity' => 'integer|min:1',
            'start_date' => 'required|date',
            'status' => 'in:pending,active,cancelled,suspended',
            'metadata' => 'nullable|array',
        ];
    }
}

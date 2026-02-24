<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class StoreDocumentRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'client_id' => 'required|uuid|exists:clients,id',
            'type' => 'required|in:quotation,proforma,invoice',
            'date' => 'required|date',
            'due_date' => 'nullable|date',
            'notes' => 'nullable|string|max:2000',
            'items' => 'required|array|min:1',
            'items.*.product_service_id' => 'nullable|uuid|exists:product_services,id',
            'items.*.item_type' => 'required|in:product,service',
            'items.*.description' => 'required|string|max:500',
            'items.*.quantity' => 'required|numeric|min:0.01',
            'items.*.price' => 'required|numeric|min:0',
            'items.*.discount_type' => 'nullable|in:percent,flat',
            'items.*.discount_value' => 'nullable|numeric|min:0',
            'items.*.tax_percent' => 'nullable|numeric|min:0|max:100',
            'items.*.unit' => 'nullable|string|max:20',
        ];
    }
}

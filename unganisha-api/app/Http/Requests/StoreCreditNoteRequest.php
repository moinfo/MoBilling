<?php

namespace App\Http\Requests;

use Illuminate\Contracts\Validation\Validator;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StoreCreditNoteRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        $tenantId = auth()->user()?->tenant_id;

        return [
            // Scope existence to the current tenant — the raw `exists` rule bypasses
            // the BelongsToTenant global scope.
            'client_id' => ['required', 'uuid', Rule::exists('clients', 'id')->where('tenant_id', $tenantId)],
            'source_invoice_id' => ['nullable', 'uuid', Rule::exists('documents', 'id')->where('tenant_id', $tenantId)],
            'cancel_source_invoice' => 'nullable|boolean',
            'date' => 'nullable|date',
            'notes' => 'nullable|string|max:2000',
            'items' => 'required|array|min:1',
            'items.*.product_service_id' => ['nullable', 'uuid', Rule::exists('product_services', 'id')->where('tenant_id', $tenantId)],
            'items.*.item_type' => 'required|in:product,service',
            'items.*.description' => 'required|string|max:500',
            'items.*.quantity' => 'required|numeric|min:0.01',
            'items.*.price' => 'required|numeric|min:0',
            'items.*.discount_type' => 'nullable|in:percent,flat',
            'items.*.discount_value' => 'nullable|numeric|min:0',
            'items.*.tax_percent' => 'nullable|numeric|min:0|max:100',
            'items.*.unit' => 'nullable|string|max:20',
            'items.*.service_from' => 'nullable|date',
            'items.*.service_to' => 'nullable|date',
        ];
    }

    public function withValidator(Validator $validator): void
    {
        $validator->after(function (Validator $validator) {
            foreach ($this->input('items', []) as $i => $item) {
                $discountType = $item['discount_type'] ?? null;
                $discountValue = $item['discount_value'] ?? null;
                if ($discountType === 'percent' && is_numeric($discountValue) && $discountValue > 100) {
                    $validator->errors()->add(
                        "items.{$i}.discount_value",
                        'Percentage discount cannot exceed 100%.'
                    );
                }
            }
        });
    }
}

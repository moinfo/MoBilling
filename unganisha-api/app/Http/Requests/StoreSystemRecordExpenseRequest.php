<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StoreSystemRecordExpenseRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        $tenantId = auth()->user()?->tenant_id;

        return [
            'system_record_id' => [
                'required', 'uuid',
                Rule::exists('system_records', 'id')
                    ->where('tenant_id', $tenantId)
                    ->where('type', 'withdraw')
                    ->whereNull('deleted_at'),
            ],
            'amount'         => 'required|numeric|min:0.01',
            'expense_date'   => 'required|date|before_or_equal:today',
            'description'    => 'required|string|max:500',
            // Attachment is explicitly optional here — unlike a deposit
            // slip, proof of spend isn't always a single document.
            'attachment'     => 'nullable|file|max:10240|mimes:pdf,jpg,jpeg,png',
        ];
    }
}

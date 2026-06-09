<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StoreSystemRecordRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        $tenantId = auth()->user()?->tenant_id;

        return [
            // Tenant-scoped exists checks so a UUID from another tenant
            // cannot be linked into this tenant's records.
            'system_id' => [
                'required', 'uuid',
                Rule::exists('systems', 'id')->where('tenant_id', $tenantId)->whereNull('deleted_at'),
            ],
            'system_property_id' => [
                'required', 'uuid',
                Rule::exists('system_properties', 'id')->where('tenant_id', $tenantId)->whereNull('deleted_at'),
            ],
            'record_date' => 'required|date|before_or_equal:today',
            'amount' => 'required|numeric|min:0',
            'notes' => 'nullable|string|max:2000',
        ];
    }
}

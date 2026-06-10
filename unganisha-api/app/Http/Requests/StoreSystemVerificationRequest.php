<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StoreSystemVerificationRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        $tenantId = auth()->user()?->tenant_id;

        return [
            'name' => 'required|string|max:255',
            'domain_name' => 'nullable|string|max:255',
            // client_id is now a FK to clients.id, tenant-scoped so a UUID
            // from another tenant cannot be linked in.
            'client_id' => [
                'nullable', 'uuid',
                Rule::exists('clients', 'id')->where('tenant_id', $tenantId)->whereNull('deleted_at'),
            ],
            'assigned_user_id' => [
                'nullable', 'uuid',
                Rule::exists('users', 'id')->where('tenant_id', $tenantId),
            ],
            'is_active' => 'sometimes|boolean',
        ];
    }
}

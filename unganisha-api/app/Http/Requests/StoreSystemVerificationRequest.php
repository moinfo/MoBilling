<?php

namespace App\Http\Requests;

use App\Models\SystemVerification;
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
            // The login the assigned staff uses to actually check the client's
            // system. Both optional — not every system needs a stored login.
            'login_username' => 'nullable|string|max:255',
            'login_password' => 'nullable|string|max:255',
            // This system's own daily check-in window — each assigned person
            // (and each system) can have a different one. Both nullable
            // together — either set a real window, or leave it unenforced.
            'window_from' => 'nullable|date_format:H:i',
            'window_to' => 'nullable|date_format:H:i|required_with:window_from|after:window_from',
            // Which daily closing figures this system's assigned staff must
            // report. Null/omitted = all of them (SystemVerification::requiredFields()).
            'required_fields' => 'nullable|array',
            'required_fields.*' => Rule::in(array_keys(SystemVerification::AVAILABLE_FIELDS)),
        ];
    }
}

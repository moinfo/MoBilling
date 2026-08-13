<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StoreClientRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        $tenantId  = auth()->user()->tenant_id;
        $clientId  = $this->route('client')?->id; // null on store, set on update

        return [
            'name'    => 'required|string|max:255',
            'email'   => [
                'nullable', 'email', 'max:255',
                Rule::unique('clients')->where('tenant_id', $tenantId)->ignore($clientId),
            ],
            'phone'   => [
                'nullable', 'string', 'max:20',
                Rule::unique('clients')->where('tenant_id', $tenantId)->ignore($clientId),
            ],
            'address' => 'nullable|string|max:1000',
            'tax_id'  => 'nullable|string|max:50',

            // WHMCS-style structured fields — all optional, purely additive
            // alongside the flat name/address above (see migration docblock).
            'first_name'   => 'nullable|string|max:255',
            'last_name'    => 'nullable|string|max:255',
            'company_name' => 'nullable|string|max:255',
            'address_1'    => 'nullable|string|max:255',
            'address_2'    => 'nullable|string|max:255',
            'city'         => 'nullable|string|max:255',
            'state'        => 'nullable|string|max:255',
            'postcode'     => 'nullable|string|max:30',
            'country'      => 'nullable|string|size:2',
        ];
    }

    public function messages(): array
    {
        return [
            'email.unique' => 'A client with this email already exists.',
            'phone.unique' => 'A client with this phone number already exists.',
        ];
    }
}

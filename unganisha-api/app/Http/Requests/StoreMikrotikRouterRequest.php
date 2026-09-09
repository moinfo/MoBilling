<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class StoreMikrotikRouterRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        $isUpdate = $this->isMethod('put') || $this->isMethod('patch');

        return [
            'name'      => 'required|string|max:255',
            'host'      => 'required|string|max:255',
            'local_login_host' => 'nullable|string|max:255',
            'api_port'  => 'nullable|integer|min:1|max:65535',
            'username'  => 'required|string|max:255',
            // Required on create; optional on update (leave blank to keep the current password).
            'password'  => [$isUpdate ? 'nullable' : 'required', 'string', 'max:255'],
            'use_tls'      => 'sometimes|boolean',
            'payment_mode' => 'sometimes|in:self_managed,platform_collected',
            'is_active'    => 'sometimes|boolean',
        ];
    }
}

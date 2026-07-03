<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StoreProductServiceRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'type' => 'required|in:product,service',
            'name' => 'required|string|max:255',
            'code' => 'nullable|string|max:50',
            'description' => 'nullable|string|max:1000',
            'price' => 'required|numeric|min:0',
            'tax_percent' => 'nullable|numeric|min:0|max:100',
            'unit' => 'nullable|string|max:20',
            'category' => 'nullable|string|max:100',
            'billing_cycle' => 'nullable|in:once,monthly,quarterly,half_yearly,yearly',
            'is_active' => 'nullable|boolean',
            // WHM/cPanel provisioning (tenant-scoped server check — never bare exists)
            'provisioning_type' => 'nullable|in:none,whm_cpanel',
            'server_id' => [
                'nullable', 'uuid', 'required_if:provisioning_type,whm_cpanel',
                Rule::exists('servers', 'id')->where('tenant_id', auth()->user()?->tenant_id),
            ],
            'cpanel_package' => 'nullable|string|max:255|required_if:provisioning_type,whm_cpanel',
            'auto_provision' => 'nullable|boolean',
            'portal_visible' => 'nullable|boolean',
        ];
    }
}

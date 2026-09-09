<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StoreWifiPlanRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        $tenantId = auth()->user()?->tenant_id;

        return [
            'mikrotik_router_id' => [
                'required', 'uuid',
                Rule::exists('mikrotik_routers', 'id')->where('tenant_id', $tenantId)->whereNull('deleted_at'),
            ],
            'name'            => 'required|string|max:255',
            'duration_value'  => 'required|integer|min:1',
            'duration_unit'   => 'required|in:hours,days,weeks',
            'price'           => 'required|numeric|min:0',
            'hotspot_profile' => 'nullable|string|max:255',
            'is_active'       => 'sometimes|boolean',
        ];
    }
}

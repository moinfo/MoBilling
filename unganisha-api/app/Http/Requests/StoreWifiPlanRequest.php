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
            // A plan needs at least one limit: a duration, a data cap, or
            // both together (e.g. "2GB, valid 1 day"). Either may be
            // omitted entirely for pure data-only or pure time-only plans.
            'duration_value'  => 'nullable|required_without:data_cap_mb|integer|min:1',
            'duration_unit'   => 'nullable|required_without:data_cap_mb|in:hours,days,weeks',
            'data_cap_mb'     => 'nullable|required_without:duration_value|integer|min:1',
            'speed_limit_mbps' => 'nullable|numeric|min:0.1|max:9999',
            'price'           => 'required|numeric|min:0',
            'hotspot_profile' => 'nullable|string|max:255',
            'is_active'       => 'sometimes|boolean',
        ];
    }
}

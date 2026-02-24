<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

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
        ];
    }
}

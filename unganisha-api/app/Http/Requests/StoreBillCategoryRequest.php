<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class StoreBillCategoryRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'parent_id' => 'nullable|uuid|exists:bill_categories,id',
            'name' => 'required|string|max:255',
            'billing_cycle' => 'nullable|in:once,monthly,quarterly,half_yearly,yearly',
            'is_active' => 'nullable|boolean',
        ];
    }
}

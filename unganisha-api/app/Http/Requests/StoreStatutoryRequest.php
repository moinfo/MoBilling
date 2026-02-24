<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class StoreStatutoryRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'name' => 'required|string|max:255',
            'bill_category_id' => 'nullable|uuid|exists:bill_categories,id',
            'amount' => 'required|numeric|min:0.01',
            'cycle' => 'required|in:once,monthly,quarterly,half_yearly,yearly',
            'issue_date' => 'required|date',
            'remind_days_before' => 'nullable|integer|min:1|max:30',
            'is_active' => 'nullable|boolean',
            'notes' => 'nullable|string|max:1000',
        ];
    }
}

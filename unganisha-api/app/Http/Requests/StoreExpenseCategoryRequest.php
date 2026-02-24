<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class StoreExpenseCategoryRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'expense_category_id' => 'nullable|uuid|exists:expense_categories,id',
            'name' => 'required|string|max:255',
            'is_active' => 'nullable|boolean',
        ];
    }
}

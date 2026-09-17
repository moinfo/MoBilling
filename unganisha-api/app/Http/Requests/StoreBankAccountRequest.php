<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class StoreBankAccountRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'bank_name' => 'required|string|max:255',
            'account_number' => 'required|string|max:255',
            'opening_balance' => 'nullable|numeric',
            // Null = old behavior (opening_balance means "before all time").
            // Set = the balance as of this exact date; records before it
            // are excluded from the statement so they aren't double-counted.
            'opening_balance_date' => 'nullable|date',
            'is_active' => 'sometimes|boolean',
        ];
    }
}

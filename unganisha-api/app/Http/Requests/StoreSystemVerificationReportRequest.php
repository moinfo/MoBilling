<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class StoreSystemVerificationReportRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'status' => 'required|in:ok,issue',
            // notes are required when reporting an issue — the whole point of
            // the workflow is that admin needs to know what's wrong.
            'notes' => 'required_if:status,issue|nullable|string|max:5000',
            // The real purpose of the check-in: the figures read off the
            // client's system after they close out for the day. Required
            // regardless of status — an "issue" report still needs the real
            // numbers, that's often exactly what reveals the issue.
            'cash' => 'required|numeric|min:0|max:999999999999.99',
            'sales' => 'required|numeric|min:0|max:999999999999.99',
            'credit' => 'required|numeric|min:0|max:999999999999.99',
            // Signed — a loss is just a negative gain, not a separate field.
            'gain_loss' => 'required|numeric|between:-999999999999.99,999999999999.99',
        ];
    }
}

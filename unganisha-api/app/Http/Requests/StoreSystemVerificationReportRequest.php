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
        ];
    }
}

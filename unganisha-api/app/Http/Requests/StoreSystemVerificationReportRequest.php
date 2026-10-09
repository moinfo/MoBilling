<?php

namespace App\Http\Requests;

use App\Models\SystemVerification;
use Illuminate\Foundation\Http\FormRequest;

class StoreSystemVerificationReportRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        // The route-bound system decides which figures it actually wants —
        // not every system shows all four. A field this system didn't ask
        // for is still accepted if sent (nullable|numeric), just not forced.
        $system = $this->route('system_verification');
        $required = $system instanceof SystemVerification
            ? $system->requiredFields()
            : array_keys(SystemVerification::AVAILABLE_FIELDS);

        $figureRule = fn (string $field, string $range) => (in_array($field, $required, true) ? 'required' : 'nullable')
            . "|numeric|{$range}";

        $rules = [
            'status' => 'required|in:ok,issue',
            // notes are required when reporting an issue — the whole point of
            // the workflow is that admin needs to know what's wrong.
            'notes' => 'required_if:status,issue|nullable|string|max:5000',
            // The real purpose of the check-in: the figures read off the
            // client's system after they close out for the day. Required
            // regardless of status — an "issue" report still needs the real
            // numbers, that's often exactly what reveals the issue — unless
            // this system didn't ask for that particular figure at all.
            'cash' => $figureRule('cash', 'min:0|max:999999999999.99'),
            'sales' => $figureRule('sales', 'min:0|max:999999999999.99'),
            'credit' => $figureRule('credit', 'min:0|max:999999999999.99'),
            // Signed — a loss is just a negative gain, not a separate field.
            'gain_loss' => $figureRule('gain_loss', 'between:-999999999999.99,999999999999.99'),
            'custom_values' => 'nullable|array',
        ];

        // Any required field that isn't one of the four built-in ones is an
        // admin-defined custom field (SystemVerificationFieldDefinition) —
        // its value lives in custom_values, keyed by the same `key`.
        $builtIn = array_keys(SystemVerification::AVAILABLE_FIELDS);
        foreach ($required as $key) {
            if (!in_array($key, $builtIn, true)) {
                $rules["custom_values.{$key}"] = 'required|numeric|between:-999999999999.99,999999999999.99';
            }
        }

        return $rules;
    }
}

<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StoreExpenseRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        $methods = $this->allowedPaymentMethods();
        $tenantId = auth()->user()?->tenant_id;

        return [
            'sub_expense_category_id' => 'nullable|uuid|exists:sub_expense_categories,id',
            // Tenant-scoped exists so a UUID from another tenant cannot be assigned.
            'petty_cash_account_id' => [
                'nullable', 'uuid',
                Rule::exists('petty_cash_accounts', 'id')->where('tenant_id', $tenantId),
            ],
            'description' => 'required|string|max:255',
            'amount' => 'required|numeric|min:0.01',
            'expense_date' => 'required|date',
            'payment_method' => ['required', 'string', Rule::in($methods)],
            'control_number' => 'nullable|string|max:255',
            'reference' => 'nullable|string|max:255',
            'notes' => 'nullable|string|max:2000',
            'attachment' => 'nullable|file|max:10240|mimes:pdf,jpg,jpeg,png,doc,docx,xls,xlsx',
            // Voucher fields — typically used only when petty_cash_account_id is set.
            'given_by_name' => 'nullable|string|max:255',
            'received_by_name' => 'nullable|string|max:255',
        ];
    }

    private function allowedPaymentMethods(): array
    {
        $tenant = auth()->user()?->tenant;
        if ($tenant && !empty($tenant->payment_methods)) {
            return collect($tenant->payment_methods)->pluck('value')->all();
        }

        return ['cash', 'bank', 'mpesa', 'card', 'other'];
    }
}

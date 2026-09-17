<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StoreSystemRecordRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        $tenantId = auth()->user()?->tenant_id;

        // Required on create, nullable on update — the existing record
        // already has a receipt on file from when it was created. A
        // "charge" (e.g. a system-generated fee/deduction) has no physical
        // slip to attach, unlike deposit/withdraw, so it's always optional.
        $isUpdate = $this->route('system_record') !== null;
        $receiptRequired = !$isUpdate && $this->input('type') !== 'charge';
        $receiptRule = [$receiptRequired ? 'required' : 'nullable', 'file', 'max:10240', 'mimes:pdf,jpg,jpeg,png'];

        return [
            // Tenant-scoped exists checks so a UUID from another tenant
            // cannot be linked into this tenant's records.
            'system_id' => [
                'required', 'uuid',
                Rule::exists('systems', 'id')->where('tenant_id', $tenantId)->whereNull('deleted_at'),
            ],
            'system_property_id' => [
                'required', 'uuid',
                Rule::exists('system_properties', 'id')->where('tenant_id', $tenantId)->whereNull('deleted_at'),
            ],
            // Optional. NULL = cash or unspecified channel.
            'bank_account_id' => [
                'nullable', 'uuid',
                Rule::exists('bank_accounts', 'id')->where('tenant_id', $tenantId)->whereNull('deleted_at'),
            ],
            'type' => 'required|in:deposit,withdraw,charge',
            // Deposit slip / transaction ID — required for deposits so the
            // same receipt can't be entered twice; whereNull('deleted_at')
            // lets a soft-deleted (wrongly entered) record's reference be
            // reused, and ->ignore() lets an update keep its own reference.
            'transaction_reference' => [
                $this->input('type') === 'deposit' ? 'required' : 'nullable',
                'string', 'max:100',
                Rule::unique('system_records', 'transaction_reference')
                    ->where('tenant_id', $tenantId)
                    ->whereNull('deleted_at')
                    ->ignore($this->route('system_record')),
            ],
            'record_date' => 'required|date|before_or_equal:today',
            'amount' => 'required|numeric|min:0',
            'notes' => 'nullable|string|max:2000',
            'receipt' => $receiptRule,
        ];
    }
}

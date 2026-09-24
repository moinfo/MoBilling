<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StoreProductServiceRequest extends FormRequest
{
    public function authorize(): bool
    {
        // Linode Server products are billing-only records tied to the tenant's Linode
        // integration — only staff who can manage Linode may create/convert them.
        if ($this->input('provisioning_type') === 'linode') {
            return (bool) $this->user()?->hasPermission('linode.manage');
        }

        return true;
    }

    /**
     * A Linode Server product is manual/billing-only: never self-orderable from the
     * portal, and carries no WHM server/package.
     */
    public function validated($key = null, $default = null)
    {
        $data = parent::validated();
        if (($data['provisioning_type'] ?? null) === 'linode') {
            $data['portal_visible'] = false;
            $data['auto_provision'] = false;
            $data['server_id'] = null;
            $data['cpanel_package'] = null;
        }

        return $key ? data_get($data, $key, $default) : $data;
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
            // Fixed calendar issue day (e.g. 25) instead of "N days before
            // the cycle renewal date" — see RecurringInvoiceService::processDayOfMonthBills().
            // Capped at 28 so it's valid in every month including February.
            'invoice_day_of_month' => 'nullable|integer|min:1|max:28',
            'is_active' => 'nullable|boolean',
            // WHM/cPanel provisioning (tenant-scoped server check — never bare exists)
            'provisioning_type' => 'nullable|in:none,whm_cpanel,linode',
            'server_id' => [
                'nullable', 'uuid', 'required_if:provisioning_type,whm_cpanel',
                Rule::exists('servers', 'id')->where('tenant_id', auth()->user()?->tenant_id),
            ],
            'cpanel_package' => 'nullable|string|max:255|required_if:provisioning_type,whm_cpanel',
            'auto_provision' => 'nullable|boolean',
            'portal_visible' => 'nullable|boolean',
        ];
    }
}

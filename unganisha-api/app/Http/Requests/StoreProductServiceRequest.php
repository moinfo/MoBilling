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
        // Same for Linode VPS products (linode_vps): they auto-provision a real,
        // billable VPS the moment the invoice is paid, so creating/editing one
        // needs the same permission as everything else Linode.
        if (in_array($this->input('provisioning_type'), ['linode', 'linode_vps'], true)) {
            return (bool) $this->user()?->hasPermission('linode.manage');
        }

        return true;
    }

    /**
     * A Linode Server product (provisioning_type=linode) is manual/billing-only:
     * never self-orderable from the portal, and carries no WHM server/package.
     * A Linode VPS product (linode_vps) is the opposite — it exists specifically
     * to be auto-provisioned, so auto_provision is always forced on; portal_visible
     * is left to the admin (default catalog validation already defaults it false
     * unless explicitly set true).
     */
    public function validated($key = null, $default = null)
    {
        $data = parent::validated();
        $type = $data['provisioning_type'] ?? null;

        if ($type === 'linode') {
            $data['portal_visible'] = false;
            $data['auto_provision'] = false;
            $data['server_id'] = null;
            $data['cpanel_package'] = null;
            $data['linode_type'] = null;
            $data['linode_region'] = null;
            $data['linode_image'] = null;
        } elseif ($type === 'linode_vps') {
            $data['auto_provision'] = true;
            $data['server_id'] = null;
            $data['cpanel_package'] = null;
            $data['linode_image'] = $data['linode_image'] ?: 'linode/ubuntu22.04';
        } else {
            $data['linode_type'] = null;
            $data['linode_region'] = null;
            $data['linode_image'] = null;
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
            'provisioning_type' => 'nullable|in:none,whm_cpanel,linode,linode_vps',
            'server_id' => [
                'nullable', 'uuid', 'required_if:provisioning_type,whm_cpanel',
                Rule::exists('servers', 'id')->where('tenant_id', auth()->user()?->tenant_id),
            ],
            'cpanel_package' => 'nullable|string|max:255|required_if:provisioning_type,whm_cpanel',
            // Linode VPS provisioning — a plan slug (e.g. g6-standard-2) and a region
            // slug (e.g. us-east), both picked from LinodeController::planCatalog()'s
            // live /linode/types + /regions lists, not free text staff could typo.
            'linode_type' => 'nullable|string|max:60|required_if:provisioning_type,linode_vps',
            'linode_region' => 'nullable|string|max:40|required_if:provisioning_type,linode_vps',
            'linode_image' => 'nullable|string|max:60',
            'auto_provision' => 'nullable|boolean',
            'portal_visible' => 'nullable|boolean',
        ];
    }
}

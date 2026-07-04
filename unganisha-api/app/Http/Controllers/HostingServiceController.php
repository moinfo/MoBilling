<?php

namespace App\Http\Controllers;

use App\Exceptions\WhmApiException;
use App\Models\ClientSubscription;
use App\Models\HostingAccount;
use App\Models\PaymentIn;
use App\Models\ProductService;
use App\Models\Server;
use App\Services\WhmService;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Admin "Products/Services" management — the WHMCS Client Profile → service tab.
 * Everything is scoped to one client + one subscription (service).
 */
class HostingServiceController extends Controller
{
    /** Selector list: this client's services as "{Product} - {domain}". */
    public function forClient(Request $request)
    {
        $request->validate(['client_id' => 'required|uuid']);

        $subs = ClientSubscription::with(['productService:id,name,category', 'hostingAccount:id,client_subscription_id,domain,status'])
            ->where('client_id', $request->client_id)
            ->orderByDesc('created_at')
            ->get()
            ->map(fn ($s) => [
                'id'           => $s->id,
                'product_name' => $s->productService?->name ?? 'Service',
                'domain'       => $s->hostingAccount?->domain ?? $s->label,
                'status'       => $s->status,
                'has_account'  => (bool) $s->hostingAccount,
            ]);

        return response()->json(['data' => $subs]);
    }

    /** Full service detail + form option lists for the edit screen. */
    public function show(ClientSubscription $clientSubscription)
    {
        $sub = $clientSubscription->load(['productService', 'hostingAccount.server', 'client:id,name']);
        $p   = $sub->productService;
        $ha  = $sub->hostingAccount;
        $meta = $sub->metadata ?? [];

        // Original order invoice → first payment + payment method.
        $orderDocId = $meta['order_document_id'] ?? $meta['document_id'] ?? null;
        $lastPayment = $orderDocId
            ? PaymentIn::withoutGlobalScopes()->where('document_id', $orderDocId)->latest('payment_date')->first()
            : null;

        $servers = Server::where('is_active', true)->withCount('hostingAccounts')->get()
            ->map(fn ($s) => [
                'id'       => $s->id,
                'label'    => "{$s->hostname} ({$s->hosting_accounts_count} accounts)",
                'hostname' => $s->hostname,
            ]);

        $products = ProductService::where('type', 'service')->where('is_active', true)
            ->where(fn ($q) => $q->whereNull('code')->orWhere('code', 'not like', 'WHMCS-P%-%'))
            ->orderBy('name')->get(['id', 'name', 'price', 'billing_cycle', 'cpanel_package'])
            ->unique('name')->values();

        $derivedRecurring = $p ? (float) $p->price * (int) $sub->quantity : null;

        return response()->json(['data' => [
            'id'            => $sub->id,
            'client'        => ['id' => $sub->client?->id, 'name' => $sub->client?->name],
            'order_document_id' => $orderDocId,
            // editable fields
            'product_service_id'   => $sub->product_service_id,
            'server_id'            => $ha?->server_id ?? $p?->server_id,
            'domain'               => $ha?->domain ?? $sub->label,
            'dedicated_ip'         => $meta['dedicated_ip'] ?? null,
            'username'             => $ha?->cpanel_username,
            'package'              => $ha?->package ?? $p?->cpanel_package,
            'status'               => $sub->status,
            'start_date'           => $sub->start_date?->toDateString(),
            'quantity'             => (int) $sub->quantity,
            'first_payment_amount' => $sub->first_payment_amount !== null
                ? (float) $sub->first_payment_amount
                : ($lastPayment ? (float) $lastPayment->amount : $derivedRecurring),
            'recurring_amount'     => $sub->recurring_amount !== null ? (float) $sub->recurring_amount : $derivedRecurring,
            'next_due_date'        => $sub->expire_date?->toDateString(),
            'termination_date'     => $meta['termination_date'] ?? null,
            'billing_cycle'        => $p?->billing_cycle,
            'payment_method'       => $sub->payment_method ?? $lastPayment?->payment_method,
            'promo_code'           => $sub->promo_code,
            // hosting account context
            'hosting_account'      => $ha ? [
                'id'             => $ha->id,
                'status'         => $ha->status,
                'server_id'      => $ha->server_id,
                'server_host'    => $ha->server?->hostname,
                'last_synced_at' => $ha->last_synced_at?->toISOString(),
                'not_on_whm'     => (bool) ($sub->metadata['not_on_whm'] ?? false),
            ] : null,
            'ssl'  => [
                'valid'      => $meta['ssl_valid'] ?? null,
                'issuer'     => $meta['ssl_issuer'] ?? null,
                'expires_at' => $meta['ssl_expires_at'] ?? null,
            ],
            'metrics' => $this->metrics($ha),
            // option lists
            'options' => [
                'servers'         => $servers,
                'products'        => $products,
                'statuses'        => ['pending', 'active', 'suspended', 'terminated', 'cancelled', 'fraud'],
                'billing_cycles'  => ['monthly', 'quarterly', 'half_yearly', 'yearly', 'once'],
                'payment_methods' => ['pesapal', 'bank', 'cash', 'cheque', 'mpesa', 'credit'],
            ],
        ]]);
    }

    /** Persist the edit form. `recalculate` re-derives recurring from product price. */
    public function update(Request $request, ClientSubscription $clientSubscription)
    {
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'product_service_id'   => ['required', 'uuid', Rule::exists('product_services', 'id')->where('tenant_id', $tenantId)],
            'status'               => ['required', Rule::in(['pending', 'active', 'suspended', 'terminated', 'cancelled', 'fraud'])],
            'domain'               => 'nullable|string|max:253',
            'dedicated_ip'         => 'nullable|string|max:45',
            'username'             => 'nullable|string|max:64',
            'package'              => 'nullable|string|max:255',
            'server_id'            => ['nullable', 'uuid', Rule::exists('servers', 'id')->where('tenant_id', $tenantId)],
            'start_date'           => 'nullable|date',
            'quantity'             => 'required|integer|min:1',
            'first_payment_amount' => 'nullable|numeric|min:0',
            'recurring_amount'     => 'nullable|numeric|min:0',
            'next_due_date'        => 'nullable|date',
            'termination_date'     => 'nullable|date',
            'payment_method'       => 'nullable|string|max:50',
            'promo_code'           => 'nullable|string|max:50',
            'recalculate'          => 'boolean',
        ]);

        $product = ProductService::findOrFail($data['product_service_id']);

        // Recalculate on Save = Yes → recurring from current product pricing.
        $recurring = $request->boolean('recalculate')
            ? (float) $product->price * (int) $data['quantity']
            : ($data['recurring_amount'] ?? null);

        $meta = $clientSubscription->metadata ?? [];
        if (array_key_exists('dedicated_ip', $data))     $meta['dedicated_ip'] = $data['dedicated_ip'];
        if (!empty($data['termination_date']))            $meta['termination_date'] = $data['termination_date'];
        elseif (array_key_exists('termination_date', $data)) unset($meta['termination_date']);

        $clientSubscription->update([
            'product_service_id'   => $data['product_service_id'],
            'label'                => $data['domain'] ?? $clientSubscription->label,
            'status'               => $data['status'],
            'start_date'           => $data['start_date'] ?? $clientSubscription->start_date,
            'expire_date'          => $data['next_due_date'] ?? $clientSubscription->expire_date,
            'quantity'             => $data['quantity'],
            'first_payment_amount' => $data['first_payment_amount'] ?? null,
            'recurring_amount'     => $recurring,
            'payment_method'       => $data['payment_method'] ?? null,
            'promo_code'           => $data['promo_code'] ?? null,
            'metadata'             => $meta,
        ]);

        // Mirror domain/username/package/server onto the hosting account row.
        if ($ha = $clientSubscription->hostingAccount) {
            $ha->update(array_filter([
                'domain'          => $data['domain'] ?? null,
                'cpanel_username' => $data['username'] ?? null,
                'package'         => $data['package'] ?? null,
                'server_id'       => $data['server_id'] ?? null,
            ], fn ($v) => $v !== null));
        }

        return $this->show($clientSubscription->fresh());
    }

    /** Module command: set the cPanel password on the server. */
    public function changePassword(Request $request, HostingAccount $hostingAccount)
    {
        $data = $request->validate(['password' => 'required|string|min:8|max:255']);

        try {
            (new WhmService($hostingAccount->server))
                ->forAccount($hostingAccount->id)
                ->resetPassword($hostingAccount->cpanel_username, $data['password']);

            return response()->json(['message' => 'cPanel password changed.']);
        } catch (WhmApiException $e) {
            return response()->json(['message' => 'Server rejected the change: ' . $e->getMessage()], 422);
        }
    }

    /** Pull live usage from the server into the account metrics. */
    public function refreshUsage(HostingAccount $hostingAccount)
    {
        try {
            $summary = (new WhmService($hostingAccount->server))
                ->forAccount($hostingAccount->id)
                ->accountSummary($hostingAccount->cpanel_username);

            $hostingAccount->update([
                'last_synced_at' => now(),
                'meta' => array_merge($hostingAccount->meta ?? [], [
                    'disk_used'    => $summary['diskused']   ?? null,
                    'disk_limit'   => $summary['disklimit']  ?? null,
                    'bw_used'      => $summary['totalbytes']  ?? ($summary['bwused'] ?? null),
                    'bw_limit'     => $summary['bwlimit']     ?? ($summary['totalbwlimit'] ?? null),
                    'email_count'  => $summary['email_accounts'] ?? null,
                    'plan'         => $summary['plan']        ?? null,
                    'usage_synced_at' => now()->toISOString(),
                ]),
            ]);

            return response()->json(['data' => $this->metrics($hostingAccount->fresh())]);
        } catch (WhmApiException $e) {
            return response()->json(['message' => 'Could not reach the server: ' . $e->getMessage()], 422);
        }
    }

    /** Metric-statistics table rows from the account's cached usage. */
    private function metrics(?HostingAccount $ha): array
    {
        $m = $ha?->meta ?? [];
        $last = $m['usage_synced_at'] ?? $ha?->last_synced_at?->toISOString();
        $row = fn ($label, $enabled, $usage) => [
            'metric'      => $label,
            'enabled'     => $enabled,
            'usage'       => $usage,
            'last_update' => $usage !== null ? $last : null,
        ];

        $disk = isset($m['disk_used']) ? "{$m['disk_used']} / " . ($m['disk_limit'] ?? '∞') : null;
        $bw   = isset($m['bw_used']) ? "{$m['bw_used']} / " . ($m['bw_limit'] ?? '∞') : null;

        return [
            $row('Disk Space',       true, $disk),
            $row('Bandwidth',        true, $bw),
            $row('Email Accounts',   true, $m['email_count'] ?? null),
            $row('Addon Domains',    true, $m['addon_domains'] ?? null),
            $row('Parked Domains',   true, $m['parked_domains'] ?? null),
            $row('Subdomains',       true, $m['subdomains'] ?? null),
            $row('MySQL® Databases', true, $m['databases'] ?? null),
        ];
    }
}

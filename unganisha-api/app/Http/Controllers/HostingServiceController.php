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

    /** WHMCS-style upgrade/downgrade options: every product + prorated charge. */
    public function upgradeOptions(ClientSubscription $clientSubscription)
    {
        $sub = $clientSubscription->load('productService');
        abort_unless($sub->productService, 422, 'Subscription has no product.');
        abort_if(config('whmcs.parallel_mode') && $sub->legacy_id, 422,
            'This service is billed in WHMCS during parallel operation — change it there until cutover.');

        $svc = app(\App\Services\Hosting\PlanChangeService::class);
        $current = $sub->productService;

        $plans = ProductService::where('type', 'service')->where('is_active', true)
            ->where('tenant_id', $sub->tenant_id)
            // same product group as the current plan (WHMCS upgrade paths)
            ->when($current->category, fn ($q) => $q->where('category', $current->category))
            ->where(fn ($q) => $q->whereNull('code')->orWhere('code', 'not like', 'WHMCS-P%-%'))
            ->orderBy('price')->get()
            ->unique('name')->values()
            ->map(fn ($p) => [
                'id'            => $p->id,
                'name'          => $p->name,
                'price'         => (float) $p->price,
                'billing_cycle' => $p->billing_cycle,
                'is_current'    => $p->id === $sub->product_service_id,
                'direction'      => (float) $p->price > (float) $current->price ? 'upgrade'
                    : ((float) $p->price < (float) $current->price ? 'downgrade' : 'same'),
                'prorated_due'    => $p->id === $sub->product_service_id ? 0.0 : $svc->proratedCharge($sub, $p),
                'prorated_credit' => ($p->id === $sub->product_service_id || !config('whmcs.credit_on_downgrade'))
                    ? 0.0 : $svc->proratedCredit($sub, $p),
            ]);

        return response()->json(['data' => [
            'current_plan'    => ['id' => $current->id, 'name' => $current->name, 'price' => (float) $current->price],
            'billing_cycle'   => $current->billing_cycle,
            'next_due_date'   => $sub->expire_date?->toDateString(),
            'quantity'        => (int) $sub->quantity,
            'plans'           => $plans,
        ]]);
    }

    /**
     * Apply an admin upgrade/downgrade.
     *   mode=invoice   → create the prorated invoice; the change applies when
     *                    it is paid (DocumentObserver → PlanChangeService::apply).
     *   mode=immediate → switch now with no charge (admin override / downgrade).
     */
    public function upgrade(Request $request, ClientSubscription $clientSubscription)
    {
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'product_service_id' => ['required', 'uuid',
                Rule::exists('product_services', 'id')->where('tenant_id', $tenantId)->where('is_active', true)],
            'mode' => 'required|in:invoice,immediate',
        ]);

        $sub = $clientSubscription->load('productService', 'hostingAccount');
        abort_if(config('whmcs.parallel_mode') && $sub->legacy_id, 422,
            'This service is billed in WHMCS during parallel operation — change it there until cutover.');
        abort_unless(in_array($sub->status, ['active', 'suspended']), 422,
            'Only active or suspended services can be upgraded/downgraded.');
        abort_if($sub->product_service_id === $data['product_service_id'], 422, 'That is already the current plan.');

        $new = ProductService::findOrFail($data['product_service_id']);
        // Constrain the target to the current plan's group (matches the offered list).
        abort_if($sub->productService->category && $new->category !== $sub->productService->category, 422,
            'Choose a plan from the same product group.');

        $svc = app(\App\Services\Hosting\PlanChangeService::class);
        $charge = $svc->proratedCharge($sub, $new);

        // Immediate: switch now, no invoice (downgrades or admin override).
        if ($data['mode'] === 'immediate' || $charge <= 0) {
            $svc->apply($sub, $new);
            return response()->json([
                'applied' => true,
                'message' => "Plan changed to {$new->name}" . ($sub->hostingAccount ? ' — cPanel package update dispatched.' : '.'),
            ]);
        }

        // Invoice: create the prorated charge (with tax) and mark the pending change.
        $taxPercent = (float) ($new->tax_percent ?? 0);
        $taxAmount  = round($charge * $taxPercent / 100, 2);
        $total      = round($charge + $taxAmount, 2);

        $document = \Illuminate\Support\Facades\DB::transaction(function () use ($tenantId, $sub, $new, $charge, $taxPercent, $taxAmount, $total) {
            // Cancel any earlier unpaid plan-change invoice so it can't be paid
            // to apply a superseded target (orphan-invoice guard).
            $priorDocId = $sub->metadata['pending_plan_change']['document_id'] ?? null;
            if ($priorDocId) {
                \App\Models\Document::withoutGlobalScopes()->where('id', $priorDocId)
                    ->whereNotIn('status', ['paid', 'cancelled'])->update(['status' => 'cancelled']);
            }

            $document = \App\Models\Document::withoutGlobalScopes()->create([
                'tenant_id'       => $tenantId,
                'client_id'       => $sub->client_id,
                'type'            => 'invoice',
                'document_number' => app(\App\Services\DocumentNumberService::class)->generate('invoice', $tenantId),
                'date'            => now()->toDateString(),
                'due_date'        => now()->toDateString(),
                'subtotal'        => $charge,
                'discount_amount' => 0,
                'tax_amount'      => $taxAmount,
                'total'           => $total,
                'status'          => 'sent',
                'notes'           => "Plan change: {$sub->productService->name} -> {$new->name} ({$sub->label})",
                'created_by'      => auth()->id(),
            ]);

            $document->items()->create([
                'item_type'   => 'service',
                'description' => "Upgrade to {$new->name} — prorated until " . ($sub->expire_date?->toDateString() ?? 'renewal'),
                'quantity'    => 1,
                'price'       => $charge,
                'tax_percent' => $taxPercent,
                'tax_amount'  => $taxAmount,
                'total'       => $total,
            ]);

            $sub->update(['metadata' => array_merge($sub->metadata ?? [], [
                'pending_plan_change' => ['product_service_id' => $new->id, 'document_id' => $document->id],
            ])]);

            return $document;
        });

        return response()->json([
            'applied'  => false,
            'document' => ['id' => $document->id, 'number' => $document->document_number, 'total' => (float) $document->total],
            'message'  => "Prorated invoice {$document->document_number} created (Tsh." . number_format($total, 2) . ') — the change applies automatically when it is paid.',
        ], 201);
    }

    /** Resend the WHMCS-style hosting welcome email (without the password). */
    public function resendWelcome(ClientSubscription $clientSubscription)
    {
        $ha = $clientSubscription->hostingAccount;
        abort_unless($ha, 422, 'This service has no hosting account to send a welcome email for.');

        $client = $clientSubscription->client;
        abort_unless($client?->email, 422, 'The client has no email address on file.');

        try {
            $client->notify(new \App\Notifications\HostingAccountProvisionedNotification($ha, null));
            return response()->json(['message' => "Welcome email sent to {$client->email}."]);
        } catch (\Throwable $e) {
            return response()->json(['message' => 'Could not send the email: ' . $e->getMessage()], 422);
        }
    }

    /** Send a free-form message (email) to the client. */
    public function sendMessage(Request $request, ClientSubscription $clientSubscription)
    {
        $data = $request->validate([
            'subject' => 'required|string|max:255',
            'body'    => 'required|string|max:20000',
        ]);

        $client = $clientSubscription->client;
        abort_unless($client?->email, 422, 'The client has no email address on file.');

        try {
            $client->notify(new \App\Notifications\ClientMessageNotification(
                auth()->user()->tenant, $data['subject'], $data['body']
            ));
            return response()->json(['message' => "Message sent to {$client->email}."]);
        } catch (\Throwable $e) {
            return response()->json(['message' => 'Could not send the message: ' . $e->getMessage()], 422);
        }
    }

    /**
     * Reset the cPanel password to a fresh strong value on the server, then
     * email the full welcome including the new password. Returns the password
     * once so the admin can note it.
     */
    public function resetPasswordAndWelcome(HostingAccount $hostingAccount)
    {
        abort_unless($hostingAccount->cpanel_username && $hostingAccount->server, 422,
            'This account is not linked to a server.');

        $password = \Illuminate\Support\Str::password(18, symbols: false) . '#7Za'; // cPanel-safe strength

        try {
            (new WhmService($hostingAccount->server))
                ->forAccount($hostingAccount->id)
                ->resetPassword($hostingAccount->cpanel_username, $password);
        } catch (WhmApiException $e) {
            return response()->json(['message' => 'Server rejected the password reset: ' . $e->getMessage()], 422);
        }

        $client = $hostingAccount->subscription?->client;
        $emailed = false;
        if ($client?->email) {
            try {
                $client->notify(new \App\Notifications\HostingAccountProvisionedNotification($hostingAccount, $password));
                $emailed = true;
            } catch (\Throwable $e) {
                \Illuminate\Support\Facades\Log::warning("Welcome email failed after reset for {$hostingAccount->domain}: {$e->getMessage()}");
            }
        }

        return response()->json([
            'password' => $password,
            'message'  => $emailed
                ? "Password reset and welcome email sent to {$client->email}."
                : 'Password reset on the server, but the welcome email could not be sent (no client email or mail error).',
        ]);
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

<?php

namespace App\Http\Controllers\Portal;

use App\Exceptions\WhmApiException;
use App\Http\Controllers\Controller;
use App\Models\HostingAccount;
use App\Services\WhmService;
use Illuminate\Http\Request;

class PortalHostingController extends Controller
{
    /** The authed client's hosting accounts (safe fields only). */
    public function index(Request $request)
    {
        $clientId = $request->user()->client_id;

        $accounts = HostingAccount::with(['server:id,name,hostname', 'subscription:id,client_id,label,expire_date'])
            ->whereHas('subscription', fn ($q) => $q->where('client_id', $clientId))
            ->whereNotIn('status', ['terminated'])
            ->orderBy('domain')
            ->get()
            ->map(fn ($a) => [
                'id'              => $a->id,
                'domain'          => $a->domain,
                'cpanel_username' => $a->cpanel_username,
                'package'         => $a->meta['plan'] ?? $a->package,
                'status'          => $a->status,
                'disk_used'       => $a->meta['disk_used'] ?? null,
                'disk_limit'      => $a->meta['disk_limit'] ?? null,
                'server_hostname' => $a->server?->hostname,
                'expires_at'      => $a->subscription?->expire_date?->toDateString(),
            ]);

        return response()->json(['data' => $accounts]);
    }

    /** cPanel tool deep-links offered as Quick Shortcuts (whitelist). */
    private const GOTO_MAP = [
        'email'      => '/frontend/jupiter/email_accounts/index.html',
        'forwarders' => '/frontend/jupiter/mail/fwds.html',
        'files'      => '/frontend/jupiter/filemanager/index.html',
        'backup'     => '/frontend/jupiter/backup/index.html',
        'domains'    => '/frontend/jupiter/domains/index.html',
        'cron'       => '/frontend/jupiter/cron/index.html',
        'mysql'      => '/frontend/jupiter/sql/index.html',
        'phpmyadmin' => '/3rdparty/phpMyAdmin/index.php',
        'stats'      => '/frontend/jupiter/stats/awstats.html',
    ];

    private function guardAccount(Request $request, HostingAccount $hostingAccount, bool $adminOnly = true): void
    {
        $user = $request->user();
        abort_unless($hostingAccount->subscription?->client_id === $user->client_id, 404);
        if ($adminOnly) {
            abort_unless($user->role === 'admin', 403, 'Only portal administrators can do this.');
        }
    }

    /** Full detail for the Service Details page. */
    public function show(Request $request, HostingAccount $hostingAccount)
    {
        $this->guardAccount($request, $hostingAccount, adminOnly: false);

        $sub = $hostingAccount->subscription?->load('productService');
        $p   = $sub?->productService;

        return response()->json(['data' => [
            'id'              => $hostingAccount->id,
            'domain'          => $hostingAccount->domain,
            'cpanel_username' => $hostingAccount->cpanel_username,
            'status'          => $hostingAccount->status,
            'package'         => $hostingAccount->meta['plan'] ?? $hostingAccount->package,
            'product_name'    => $p?->name,
            'product_group'   => $p?->category,
            'price'           => (float) ($p?->price ?? 0),
            'billing_cycle'   => $p?->billing_cycle,
            'registered_at'   => $sub?->start_date?->toDateString(),
            'next_due'        => $sub?->expire_date?->toDateString(),
            'disk_used'       => $hostingAccount->meta['disk_used'] ?? null,
            'disk_limit'      => $hostingAccount->meta['disk_limit'] ?? null,
            'last_synced_at'  => $hostingAccount->last_synced_at?->toISOString(),
            'shortcuts'       => array_keys(self::GOTO_MAP),
        ]]);
    }

    /** Live usage refresh (read-only accountsummary). */
    public function refreshUsage(Request $request, HostingAccount $hostingAccount)
    {
        $this->guardAccount($request, $hostingAccount, adminOnly: false);

        try {
            $summary = (new WhmService($hostingAccount->server))
                ->forAccount($hostingAccount->id)
                ->accountSummary($hostingAccount->cpanel_username);

            $hostingAccount->update([
                'last_synced_at' => now(),
                'meta' => array_merge($hostingAccount->meta ?? [], [
                    'disk_used'  => $summary['diskused'] ?? null,
                    'disk_limit' => $summary['disklimit'] ?? null,
                    'plan'       => $summary['plan'] ?? null,
                ]),
            ]);

            return response()->json(['data' => [
                'disk_used'      => $hostingAccount->fresh()->meta['disk_used'] ?? null,
                'disk_limit'     => $hostingAccount->fresh()->meta['disk_limit'] ?? null,
                'last_synced_at' => now()->toISOString(),
            ]]);
        } catch (WhmApiException) {
            return response()->json(['message' => 'Could not reach the hosting server — try again later.'], 422);
        }
    }

    /** One-time cPanel/Webmail login URL. Portal admins only — SSO grants full hosting control. */
    public function sso(Request $request, HostingAccount $hostingAccount)
    {
        $this->guardAccount($request, $hostingAccount);
        abort_unless($hostingAccount->status === 'active', 422, 'This hosting account is not active.');

        $data = $request->validate([
            'service' => 'nullable|in:cpanel,webmail',
            'goto'    => 'nullable|string|in:' . implode(',', array_keys(self::GOTO_MAP)),
        ]);

        $service = ($data['service'] ?? 'cpanel') === 'webmail' ? 'webmaild' : 'cpaneld';
        $goto    = $service === 'cpaneld' ? (self::GOTO_MAP[$data['goto'] ?? ''] ?? null) : null;

        try {
            $url = (new WhmService($hostingAccount->server))
                ->forAccount($hostingAccount->id)
                ->ssoUrl($hostingAccount->cpanel_username, $service, $goto);

            return response()->json(['url' => $url]);
        } catch (WhmApiException $e) {
            return response()->json(['message' => 'Could not open the control panel right now. Please try again later.'], 422);
        }
    }

    /** Available plans for upgrade/downgrade with the prorated charge for each. */
    public function upgradeOptions(Request $request, HostingAccount $hostingAccount)
    {
        $this->guardAccount($request, $hostingAccount, adminOnly: false);

        $sub = $hostingAccount->subscription?->load('productService');
        abort_unless($sub && $sub->productService, 422, 'Subscription data missing.');

        $svc = app(\App\Services\Hosting\PlanChangeService::class);

        $plans = \App\Models\ProductService::withoutGlobalScopes()
            ->where('tenant_id', $request->user()->tenant_id)
            ->where('is_active', true)
            ->where('portal_visible', true)
            ->where('provisioning_type', 'whm_cpanel')
            ->where('category', $sub->productService->category)
            // exclude WHMCS billing-variant records (same rule as the catalog)
            ->where(fn ($q) => $q->whereNull('code')->orWhere('code', 'not like', 'WHMCS-P%-%'))
            ->orderBy('price')
            ->get()
            ->unique('name')
            ->values()
            ->map(fn ($p) => [
                'id'            => $p->id,
                'name'          => $p->name,
                'price'         => (float) $p->price,
                'billing_cycle' => $p->billing_cycle,
                'is_current'    => $p->id === $sub->product_service_id,
                'due_now'       => $p->id === $sub->product_service_id ? 0.0 : $svc->proratedCharge($sub, $p),
            ]);

        return response()->json(['data' => [
            'current_plan' => $sub->productService->name,
            'next_due'     => $sub->expire_date?->toDateString(),
            'plans'        => $plans,
        ]]);
    }

    /** Request the plan change: free/downgrade applies now; upgrade creates a prorated invoice. */
    public function upgrade(Request $request, HostingAccount $hostingAccount)
    {
        $this->guardAccount($request, $hostingAccount);
        abort_unless($hostingAccount->status === 'active', 422, 'This hosting account is not active.');

        $user = $request->user();
        $data = $request->validate([
            'product_service_id' => ['required', 'uuid',
                \Illuminate\Validation\Rule::exists('product_services', 'id')
                    ->where('tenant_id', $user->tenant_id)->where('is_active', true)
                    ->where('provisioning_type', 'whm_cpanel')],
        ]);

        $sub = $hostingAccount->subscription?->load('productService');
        abort_unless($sub, 422, 'Subscription data missing.');
        abort_if(config('whmcs.parallel_mode') && $sub->legacy_id, 422,
            'This service cannot be changed online yet — please contact us.');
        abort_if($sub->product_service_id === $data['product_service_id'], 422, 'That is already your current plan.');

        $new = \App\Models\ProductService::withoutGlobalScopes()->find($data['product_service_id']);
        // Only within the same product group (matches the offered list).
        abort_if($sub->productService->category && $new->category !== $sub->productService->category, 422,
            'Please choose a plan from the same group.');

        $svc = app(\App\Services\Hosting\PlanChangeService::class);
        $charge = $svc->proratedCharge($sub, $new);

        if ($charge <= 0) {
            $svc->apply($sub, $new);

            return response()->json([
                'message' => "Plan changed to {$new->name} — your hosting package is being updated now.",
            ]);
        }

        $taxPercent = (float) ($new->tax_percent ?? 0);
        $taxAmount  = round($charge * $taxPercent / 100, 2);
        $total      = round($charge + $taxAmount, 2);

        $document = \Illuminate\Support\Facades\DB::transaction(function () use ($user, $sub, $new, $charge, $taxPercent, $taxAmount, $total) {
            // Supersede any earlier unpaid plan-change invoice.
            $priorDocId = $sub->metadata['pending_plan_change']['document_id'] ?? null;
            if ($priorDocId) {
                \App\Models\Document::withoutGlobalScopes()->where('id', $priorDocId)
                    ->whereNotIn('status', ['paid', 'cancelled'])->update(['status' => 'cancelled']);
            }

            $document = \App\Models\Document::withoutGlobalScopes()->create([
                'tenant_id'       => $user->tenant_id,
                'client_id'       => $user->client_id,
                'type'            => 'invoice',
                'document_number' => app(\App\Services\DocumentNumberService::class)->generate('invoice', $user->tenant_id),
                'date'            => now()->toDateString(),
                'due_date'        => now()->toDateString(),
                'subtotal'        => $charge,
                'discount_amount' => 0,
                'tax_amount'      => $taxAmount,
                'total'           => $total,
                'status'          => 'sent',
                'notes'           => "Plan upgrade: {$sub->productService->name} -> {$new->name} ({$sub->label})",
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
                'pending_plan_change' => [
                    'product_service_id' => $new->id,
                    'document_id'        => $document->id,
                ],
            ])]);

            return $document;
        });

        return response()->json([
            'data'    => ['document_id' => $document->id, 'document_number' => $document->document_number, 'total' => (float) $document->total],
            'message' => "Upgrade invoice {$document->document_number} created (Tsh." . number_format($total, 2) . ' prorated) — the upgrade applies automatically when it is paid.',
        ], 201);
    }

    /** Change the cPanel password (portal admins only). */
    public function changePassword(Request $request, HostingAccount $hostingAccount)
    {
        $this->guardAccount($request, $hostingAccount);
        abort_unless($hostingAccount->status === 'active', 422, 'This hosting account is not active.');

        $data = $request->validate([
            'password' => 'required|string|min:12|max:64|confirmed',
        ]);

        try {
            (new WhmService($hostingAccount->server))
                ->forAccount($hostingAccount->id)
                ->resetPassword($hostingAccount->cpanel_username, $data['password']);

            return response()->json(['message' => 'cPanel password changed.']);
        } catch (WhmApiException $e) {
            return response()->json(['message' => 'Password change failed: ' . $e->getMessage()], 422);
        }
    }

    /** Request cancellation — opens a support ticket for staff to action. */
    public function requestCancellation(Request $request, HostingAccount $hostingAccount)
    {
        $this->guardAccount($request, $hostingAccount);

        $data = $request->validate([
            'reason' => 'required|string|max:2000',
            'when'   => 'required|in:immediate,end_of_period',
        ]);

        $user = $request->user();
        $whenLabel = $data['when'] === 'immediate' ? 'Immediately' : 'At the end of the billing period';

        $ticket = \App\Models\Ticket::create([
            'tenant_id'     => $user->tenant_id,
            'client_id'     => $user->client_id,
            'ticket_number' => \App\Models\Ticket::nextNumber($user->tenant_id),
            'subject'       => "Cancellation request: {$hostingAccount->domain}",
            'status'        => 'open',
            'priority'      => 'high',
            'opened_by'     => $user->id,
            'last_reply_at' => now(),
        ]);

        $ticket->replies()->create([
            'tenant_id'      => $user->tenant_id,
            'author_type'    => 'client',
            'client_user_id' => $user->id,
            'message'        => "Service: {$hostingAccount->domain} ({$hostingAccount->cpanel_username})\nCancel: {$whenLabel}\n\nReason:\n{$data['reason']}",
        ]);

        try {
            foreach (\App\Http\Controllers\TicketController::staffToNotify($ticket) as $staff) {
                $staff->notify(new \App\Notifications\TicketActivityStaffNotification($ticket, 'opened'));
            }
        } catch (\Throwable) {
            // notification failure must not block the request
        }

        return response()->json([
            'message' => "Cancellation request submitted as ticket {$ticket->ticket_number} — our team will confirm shortly.",
        ], 201);
    }
}

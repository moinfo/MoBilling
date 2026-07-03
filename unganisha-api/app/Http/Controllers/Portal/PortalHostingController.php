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

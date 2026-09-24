<?php

namespace App\Http\Controllers\Portal;

use App\Exceptions\LinodeApiException;
use App\Http\Controllers\Controller;
use App\Models\ClientSubscription;
use App\Models\LinodeAccount;
use App\Models\LinodeAuditLog;
use App\Models\LinodeDomainRequest;
use App\Models\LinodeResource;
use App\Models\Ticket;
use App\Models\User;
use App\Notifications\LinodeDomainRequestNotification;
use App\Services\Linode\DnsMapping;
use App\Services\Linode\LinodeService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Notification;

/**
 * Client self-service for a Linode server billed through the client's own subscription.
 * Clients can ONLY reboot (never shutdown/boot/delete), see the domains mapped to their server,
 * request a domain (staff decide) and open a support ticket. Remote ids / tokens are never returned.
 */
class PortalLinodeController extends Controller
{
    private const REBOOT_PER_SERVER_HOUR = 2;
    private const REBOOT_PER_CLIENT_DAY = 5;
    private const MAX_PENDING_REQUESTS = 5;
    private const MAX_TICKETS_PER_SERVER_DAY = 3;

    /** The client's OWN active, linked, live instance — anything else is a 404 (never reveals other clients' servers). */
    private function ownServer(Request $request, string $id): LinodeResource
    {
        $user = $request->user();
        $srv = LinodeResource::withoutGlobalScopes()
            ->where('id', $id)->where('tenant_id', $user->tenant_id)->where('client_id', $user->client_id)
            ->where('type', 'instance')->whereNotNull('client_subscription_id')->first();
        abort_unless($srv, 404, 'Not found');
        $sub = ClientSubscription::withoutGlobalScopes()->where('id', $srv->client_subscription_id)
            ->where('client_id', $user->client_id)->where('tenant_id', $user->tenant_id)->where('status', 'active')->first();
        abort_unless($sub, 404, 'Not found');
        return $srv;
    }

    private function audit(Request $request, LinodeResource $srv, string $action, array $extra = [], int $status = 200, ?string $error = null): void
    {
        $user = $request->user();
        LinodeAuditLog::withoutGlobalScopes()->create([
            'tenant_id' => $srv->tenant_id, 'user_id' => $user->id, 'linode_account_id' => $srv->linode_account_id,
            'action' => $action, 'target' => "{$srv->label} #{$srv->remote_id}",
            'request' => ['server_id' => $srv->id, 'server_label' => $srv->label, 'client_id' => $user->client_id, 'portal_user_id' => $user->id, 'portal_user' => $user->email] + $extra,
            'response_status' => $status, 'error' => $error ? mb_substr($error, 0, 250) : null,
        ]);
    }

    private function serverFacts(LinodeResource $srv): array
    {
        return ['id' => $srv->id, 'name' => $srv->label, 'ip' => $srv->ipv4[0] ?? null, 'region' => $srv->region, 'status' => $srv->status];
    }

    /** The client's own active, linked servers (same rule as ownServer). */
    public function index(Request $request): JsonResponse
    {
        $user = $request->user();
        $subIds = ClientSubscription::withoutGlobalScopes()->where('tenant_id', $user->tenant_id)
            ->where('client_id', $user->client_id)->where('status', 'active')->pluck('id');
        $servers = LinodeResource::withoutGlobalScopes()
            ->where('tenant_id', $user->tenant_id)->where('client_id', $user->client_id)
            ->where('type', 'instance')->whereIn('client_subscription_id', $subIds)->orderBy('label')->get();

        return response()->json(['data' => $servers->map(fn ($r) => $this->serverFacts($r) + ['plan' => $r->plan])->values()]);
    }

    // ── overview: server facts + mapped domains + this client's requests ──

    public function show(Request $request, string $server): JsonResponse
    {
        $srv = $this->ownServer($request, $server);
        $clientId = $request->user()->client_id;

        $ipIndex = DnsMapping::buildIpIndex([['id' => $srv->id, 'ipv4' => $srv->ipv4 ?? [], 'ipv6' => $srv->ipv6]]);
        $domains = LinodeResource::withoutGlobalScopes()
            ->where('tenant_id', $srv->tenant_id)->where('client_id', $clientId)->where('type', 'domain')
            ->where(fn ($q) => $q->whereNull('status')->orWhere('status', '!=', 'gone'))->orderBy('label')->get()
            ->filter(function ($d) use ($ipIndex, $srv) {
                $dns = $d->meta['dns'] ?? null;
                if (!$dns || empty($dns['fetched_at'])) return false;
                $m = DnsMapping::match($dns['apex_ips'] ?? [], $dns['www_ips'] ?? [], $ipIndex);
                return in_array($srv->id, $m['instance_ids'], true);
            })
            ->map(fn ($d) => ['name' => $d->label, 'checked_at' => $d->meta['dns']['fetched_at'] ?? null])->values();

        $requests = LinodeDomainRequest::withoutGlobalScopes()
            ->where('tenant_id', $srv->tenant_id)->where('client_id', $clientId)->where('linode_resource_id', $srv->id)
            ->orderByDesc('created_at')->limit(20)->get()
            ->map(fn ($r) => ['id' => $r->id, 'domain' => $r->domain, 'status' => $r->status, 'note' => $r->note, 'created_at' => $r->created_at?->toIso8601String()])->values();

        return response()->json(['data' => ['server' => $this->serverFacts($srv), 'domains' => $domains, 'requests' => $requests]]);
    }

    // ── 1. reboot (the ONLY power action clients get) ──

    public function reboot(Request $request, string $server): JsonResponse
    {
        $data = $request->validate(['confirm_label' => 'required|string|max:255']);
        $srv = $this->ownServer($request, $server);
        $user = $request->user();
        abort_unless($user->role === 'admin', 403, 'Only portal administrators can reboot the server.');
        $refuse = function (string $msg, int $code, string $why) use ($request, $srv) {
            $this->audit($request, $srv, 'portal.server_reboot_refused', ['reason' => $why], $code, $msg);
            return response()->json(['message' => $msg], $code);
        };

        $account = LinodeAccount::withoutGlobalScopes()->where('id', $srv->linode_account_id)->where('tenant_id', $srv->tenant_id)->first();
        if (!$account || $account->status !== 'active') return $refuse('Reboot is not available for this server right now. Please contact support.', 422, 'account_inactive');
        if ($srv->status === 'gone') return $refuse('This server no longer exists.', 422, 'gone');
        if ($data['confirm_label'] !== $srv->label) return $refuse('Type the exact server name to confirm.', 422, 'wrong_confirm');

        $target = "{$srv->label} #{$srv->remote_id}";
        $hour = LinodeAuditLog::withoutGlobalScopes()->where('tenant_id', $srv->tenant_id)->where('created_at', '>=', now()->subHour());
        if ((clone $hour)->where('linode_account_id', $account->id)->where('target', $target)->whereIn('action', ['portal.server_reboot', 'server.power'])->count() >= self::REBOOT_PER_SERVER_HOUR) {
            return $refuse('Limit reached: at most ' . self::REBOOT_PER_SERVER_HOUR . ' reboots per server per hour. Please try again later.', 429, 'server_hour_limit');
        }
        $day = LinodeAuditLog::withoutGlobalScopes()->where('tenant_id', $srv->tenant_id)->where('action', 'portal.server_reboot')
            ->where('created_at', '>=', now()->subDay())->where('request->client_id', $user->client_id);
        if ($day->count() >= self::REBOOT_PER_CLIENT_DAY) {
            return $refuse('Limit reached: at most ' . self::REBOOT_PER_CLIENT_DAY . ' reboots per day. Please contact support.', 429, 'client_day_limit');
        }
        // staff-wide safety net shared with the staff power() limit (20/hour/tenant)
        if ((clone $hour)->whereIn('action', ['portal.server_reboot', 'server.power'])->count() >= 20) {
            return $refuse('Too many server actions right now. Please try again later.', 429, 'tenant_hour_limit');
        }

        try {
            $before = (new LinodeService($account))->powerAction($srv->remote_id, 'reboot');
        } catch (\DomainException $e) {
            return $refuse($e->getMessage(), 409, 'not_running');
        } catch (LinodeApiException $e) {
            $this->audit($request, $srv, 'portal.server_reboot', ['result' => 'failed'], $e->httpStatus ?: 502, $e->getMessage());
            return response()->json(['message' => 'The reboot could not be started. Please try again in a minute or contact support.'], 422);
        }

        $srv->status = LinodeService::POWER_OPTIMISTIC['reboot'];
        $srv->save();
        $this->audit($request, $srv, 'portal.server_reboot', ['result' => 'success', 'status_before' => $before]);

        return response()->json(['message' => "Reboot started for {$srv->label}. It usually takes 1-2 minutes.", 'data' => $this->serverFacts($srv)]);
    }

    // ── 3. request a domain (no Linode call here) ──

    public function requestDomain(Request $request, string $server): JsonResponse
    {
        $data = $request->validate(['domain' => 'required|string|max:253']);
        $srv = $this->ownServer($request, $server);
        $user = $request->user();
        abort_unless($user->role === 'admin', 403, 'Only portal administrators can request domains.');

        try {
            $domain = LinodeService::validateDomainName($data['domain']);
        } catch (\InvalidArgumentException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }
        if ($srv->status === 'gone' || empty($srv->ipv4[0])) {
            return response()->json(['message' => 'Domains cannot be added to this server right now. Please contact support.'], 422);
        }

        $reqs = LinodeDomainRequest::withoutGlobalScopes()->where('tenant_id', $srv->tenant_id);
        if ((clone $reqs)->where('client_id', $user->client_id)->where('status', 'pending')->count() >= self::MAX_PENDING_REQUESTS) {
            return response()->json(['message' => 'You already have ' . self::MAX_PENDING_REQUESTS . ' pending domain requests. Please wait for them to be processed.'], 422);
        }
        $exists = LinodeResource::withoutGlobalScopes()->where('tenant_id', $srv->tenant_id)->where('type', 'domain')->where('label', $domain)
            ->where(fn ($q) => $q->whereNull('status')->orWhere('status', '!=', 'gone'))->exists();
        if ($exists) {
            return response()->json(['message' => "$domain is already set up. If it is yours and not working, use \"Omba msaada\"."], 422);
        }
        if ((clone $reqs)->where('domain', $domain)->whereIn('status', ['pending', 'approved'])->exists()) {
            return response()->json(['message' => "$domain has already been requested."], 422);
        }

        $row = new LinodeDomainRequest([
            'tenant_id' => $srv->tenant_id, 'client_id' => $user->client_id, 'linode_resource_id' => $srv->id,
            'domain' => $domain, 'status' => 'pending', 'requested_by' => $user->id,
        ]);
        $row->save();
        $this->audit($request, $srv, 'portal.domain_request', ['domain' => $domain, 'request_id' => $row->id]);

        try {
            $staff = User::withPermission($srv->tenant_id, 'linode.manage');
            if ($staff->isNotEmpty()) {
                Notification::send($staff, new LinodeDomainRequestNotification($row->load('client'), 'requested', null, $srv->label));
            }
        } catch (\Throwable $e) {
            report($e);
        }

        return response()->json([
            'message' => "Request received for $domain. We will add it to your server and notify you.",
            'data' => ['id' => $row->id, 'domain' => $domain, 'status' => 'pending'],
        ], 201);
    }

    // ── 4. support ticket, same path as the normal portal ticket ──

    public function supportTicket(Request $request, string $server): JsonResponse
    {
        $request->validate(['message' => 'nullable|string|max:5000']);
        $srv = $this->ownServer($request, $server);
        $user = $request->user();

        $related = "Linode server: {$srv->label}";
        $today = Ticket::withoutGlobalScopes()->where('tenant_id', $srv->tenant_id)->where('client_id', $user->client_id)
            ->where('related_service', $related)->where('created_at', '>=', now()->subDay())->count();
        if ($today >= self::MAX_TICKETS_PER_SERVER_DAY) {
            return response()->json(['message' => 'You have already opened several tickets for this server today. Please reply on an existing ticket.'], 429);
        }

        $body = "Server: {$srv->label}\nIP: " . ($srv->ipv4[0] ?? '-') . "\nRegion: " . ($srv->region ?? '-') . "\nStatus: " . ($srv->status ?? '-')
            . "\n\n" . (trim((string) $request->input('message')) ?: 'The client asked for help with this server.');

        $request->merge(['subject' => "Server support: {$srv->label}", 'message' => $body, 'priority' => 'medium', 'department' => 'support', 'related_service' => $related]);
        $resp = app(PortalTicketController::class)->store($request);
        $this->audit($request, $srv, 'portal.server_support_ticket', ['ticket' => $resp->getData(true)['data']['ticket_number'] ?? null], $resp->getStatusCode());

        return $resp;
    }
}

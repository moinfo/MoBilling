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
use App\Services\Linode\LinodeDomainProvisioner;
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
    private const MAX_DOMAIN_ADDS_PER_DAY = 10;
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

    /** Same rule as the domains table: the stored DNS mapping says this domain currently points at this server. */
    private function mappedToServer(LinodeResource $d, LinodeResource $srv): bool
    {
        $dns = $d->meta['dns'] ?? null;
        if (!$dns || empty($dns['fetched_at'])) return false;
        $ipIndex = DnsMapping::buildIpIndex([['id' => $srv->id, 'ipv4' => $srv->ipv4 ?? [], 'ipv6' => $srv->ipv6]]);
        $m = DnsMapping::match($dns['apex_ips'] ?? [], $dns['www_ips'] ?? [], $ipIndex);
        return in_array($srv->id, $m['instance_ids'], true);
    }

    /** The client's own live domain that is currently mapped to $srv; anything else is a 404. */
    private function ownDomain(Request $request, LinodeResource $srv, string $id): LinodeResource
    {
        $user = $request->user();
        $d = LinodeResource::withoutGlobalScopes()->where('id', $id)->where('type', 'domain')
            ->where('tenant_id', $user->tenant_id)->where('client_id', $user->client_id)
            ->where(fn ($q) => $q->whereNull('status')->orWhere('status', '!=', 'gone'))->first();
        abort_unless($d && $this->mappedToServer($d, $srv), 404, 'Not found');
        return $d;
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

        $domains = LinodeResource::withoutGlobalScopes()
            ->where('tenant_id', $srv->tenant_id)->where('client_id', $clientId)->where('type', 'domain')
            ->where(fn ($q) => $q->whereNull('status')->orWhere('status', '!=', 'gone'))->orderBy('label')->get()
            ->filter(fn ($d) => $this->mappedToServer($d, $srv))
            ->map(function ($d) use ($clientId) {
                $ours = $d->domain_id ? \App\Models\Domain::withoutGlobalScopes()->where('id', $d->domain_id)->where('client_id', $clientId)->first() : null;
                return [
                    'id' => $d->id, 'registered_domain_id' => $ours?->id,
                    'name' => $d->label, 'checked_at' => $d->meta['dns']['fetched_at'] ?? null,
                    'apex_ips' => $d->meta['dns']['apex_ips'] ?? [], 'www_ips' => $d->meta['dns']['www_ips'] ?? [],
                    'registered' => (bool) $ours, 'registration_status' => $ours?->status, 'expires_at' => $ours?->expires_at?->toDateString(),
                ];
            })->values();

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
        $data = $request->validate([
            'domain' => 'required|string|max:253', 'soa_email' => 'nullable|email|max:255',
            'ttl' => 'nullable|integer', 'point_to_server' => 'nullable|boolean',
        ]);
        $srv = $this->ownServer($request, $server);
        $user = $request->user();
        abort_unless($user->role === 'admin', 403, 'Only portal administrators can add domains.');
        $point = !array_key_exists('point_to_server', $data) || $data['point_to_server'] === null ? true : (bool) $data['point_to_server'];

        try {
            $domain = LinodeService::validateDomainName($data['domain']);
            $ttl = isset($data['ttl']) ? LinodeService::validateTtl($data['ttl']) : null;
        } catch (\InvalidArgumentException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }
        if ($srv->status === 'gone' || empty($srv->ipv4[0])) {
            return response()->json(['message' => 'Domains cannot be added to this server right now. Please contact support.'], 422);
        }

        $reqs = LinodeDomainRequest::withoutGlobalScopes()->where('tenant_id', $srv->tenant_id);
        if ((clone $reqs)->where('client_id', $user->client_id)->where('created_at', '>=', now()->subDay())->count() >= self::MAX_DOMAIN_ADDS_PER_DAY) {
            return response()->json(['message' => 'You have reached the limit of ' . self::MAX_DOMAIN_ADDS_PER_DAY . ' domains per day. Try again tomorrow or use "Request server support".'], 429);
        }
        $exists = LinodeResource::withoutGlobalScopes()->where('tenant_id', $srv->tenant_id)->where('type', 'domain')->where('label', $domain)
            ->where(fn ($q) => $q->whereNull('status')->orWhere('status', '!=', 'gone'))->exists();
        if ($exists) {
            return response()->json(['message' => "$domain is already set up. If it is yours and not working, use \"Request server support\"."], 422);
        }
        $account = LinodeAccount::withoutGlobalScopes()->where('id', $srv->linode_account_id)->where('tenant_id', $srv->tenant_id)->first();
        if (!$account || $account->status !== 'active') {
            return response()->json(['message' => 'Domains cannot be added to this server right now. Please contact support.'], 422);
        }

        // Added straight away (no staff approval). The row is kept as an already-approved record for history/limits.
        $row = new LinodeDomainRequest([
            'tenant_id' => $srv->tenant_id, 'client_id' => $user->client_id, 'linode_resource_id' => $srv->id,
            'domain' => $domain, 'status' => 'approved', 'requested_by' => $user->id, 'decided_at' => now(),
            'note' => 'Added directly by the client',
        ]);
        try {
            $out = app(LinodeDomainProvisioner::class)->add($account, $domain, $data['soa_email'] ?? $account->soa_email, $ttl, $point ? $srv : null, $user->client_id);
        } catch (\Throwable $e) {
            $this->audit($request, $srv, 'portal.domain_add', ['domain' => $domain], 502, $e->getMessage());
            return response()->json(['message' => 'This domain could not be added (it may already exist, or there was an error). Try again later or use "Request server support".'], 422);
        }
        $row->save();
        $this->audit($request, $srv, 'portal.domain_add', ['domain' => $domain, 'request_id' => $row->id, 'records_created' => $out['records_created'] ?? null, 'point_to_server' => $point, 'ttl' => $ttl]);

        return response()->json([
            'message' => "$domain was added to your server. Now set the Linode nameservers at your domain registrar.",
            'data' => ['id' => $row->id, 'domain' => $domain, 'status' => 'approved', 'records_created' => $out['records_created'] ?? 0, 'pointed' => $point, 'nameservers' => LinodeService::NAMESERVERS],
        ], 201);
    }

    // ── DNS records of a domain on the client's server (add / edit only; never delete, NS/SOA locked) ──

    private const DNS_WRITES_PER_CLIENT_HOUR = 20;
    private const MAX_RECORDS_PER_DOMAIN = 50;
    private const DNS_WRITE_ACTIONS = ['portal.dns_record_add', 'portal.dns_record_edit', 'portal.dns_point_to_server', 'portal.dns_soa_edit'];
    private const DNS_GENERIC_ERROR = 'The DNS request could not be completed right now. Try again later or use "Request server support".';

    private function dnsContext(Request $request, string $server, string $domainResource, bool $write): array
    {
        $srv = $this->ownServer($request, $server);
        $dom = $this->ownDomain($request, $srv, $domainResource);
        if ($write) abort_unless($request->user()->role === 'admin', 403, 'Only portal administrators can change DNS records.');
        $account = LinodeAccount::withoutGlobalScopes()->where('id', $dom->linode_account_id)->where('tenant_id', $srv->tenant_id)->first();
        abort_unless($account && $account->status === 'active', 404, 'Not found');
        return [$srv, $dom, new LinodeService($account)];
    }

    private function safeRecord(array $r): array
    {
        $out = ['id' => $r['id'] ?? null];
        foreach (['type', 'name', 'target', 'ttl_sec', 'priority', 'weight', 'port', 'service', 'protocol', 'tag'] as $k) {
            if (array_key_exists($k, $r)) $out[$k] = $r[$k];
        }
        $out['locked'] = in_array($r['type'] ?? '', ['NS', 'SOA'], true);
        return $out;
    }

    private function dnsAudit(Request $request, LinodeResource $srv, LinodeResource $dom, string $action, array $extra, int $status = 200, ?string $error = null): void
    {
        $this->audit($request, $srv, $action, ['domain' => $dom->label] + $extra, $status, $error);
    }

    /** Refuses when the client already made too many DNS writes this hour; null when allowed. */
    private function dnsLimited(Request $request, LinodeResource $srv): ?JsonResponse
    {
        $n = LinodeAuditLog::withoutGlobalScopes()->where('tenant_id', $srv->tenant_id)->whereIn('action', self::DNS_WRITE_ACTIONS)
            ->where('created_at', '>=', now()->subHour())->where('request->client_id', $request->user()->client_id)->count();
        return $n >= self::DNS_WRITES_PER_CLIENT_HOUR
            ? response()->json(['message' => 'You have reached the limit of ' . self::DNS_WRITES_PER_CLIENT_HOUR . ' DNS changes per hour. Try again later.'], 429)
            : null;
    }

    public function dnsRecords(Request $request, string $server, string $domainResource): JsonResponse
    {
        [, $dom, $svc] = $this->dnsContext($request, $server, $domainResource, false);
        try {
            $rows = array_map(fn ($r) => $this->safeRecord($r), $svc->listRecords($dom->remote_id));
        } catch (\Throwable $e) {
            return response()->json(['message' => self::DNS_GENERIC_ERROR], 422);
        }
        return response()->json(['data' => $rows, 'meta' => ['nameservers' => LinodeService::NAMESERVERS, 'max_records' => self::MAX_RECORDS_PER_DOMAIN]]);
    }

    private function soaFacts(array $d, LinodeResource $dom): array
    {
        return ['domain' => $dom->label, 'soa_email' => $d['soa_email'] ?? null, 'ttl_sec' => (int) ($d['ttl_sec'] ?? 0), 'refresh_sec' => (int) ($d['refresh_sec'] ?? 0),
            'retry_sec' => (int) ($d['retry_sec'] ?? 0), 'expire_sec' => (int) ($d['expire_sec'] ?? 0)];
    }

    /** Live SOA info of the domain (like the header of Linode's domain page). */
    public function dnsDomain(Request $request, string $server, string $domainResource): JsonResponse
    {
        [, $dom, $svc] = $this->dnsContext($request, $server, $domainResource, false);
        try {
            $d = $svc->getDomain($dom->remote_id);
        } catch (\Throwable $e) {
            return response()->json(['message' => self::DNS_GENERIC_ERROR], 422);
        }
        return response()->json(['data' => $this->soaFacts($d, $dom), 'meta' => ['ttls' => LinodeService::SOA_TTLS]]);
    }

    public function dnsSoaUpdate(Request $request, string $server, string $domainResource): JsonResponse
    {
        $input = $request->validate(['soa_email' => 'nullable|email|max:255', 'ttl_sec' => 'nullable|integer', 'refresh_sec' => 'nullable|integer', 'retry_sec' => 'nullable|integer', 'expire_sec' => 'nullable|integer']);
        [$srv, $dom, $svc] = $this->dnsContext($request, $server, $domainResource, true);
        if ($limited = $this->dnsLimited($request, $srv)) return $limited;
        try {
            $clean = LinodeService::validateSoa(array_filter($input, fn ($v) => $v !== null));
            $d = $svc->updateDomain($dom->remote_id, $clean);
        } catch (\InvalidArgumentException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        } catch (\Throwable $e) {
            $this->dnsAudit($request, $srv, $dom, 'portal.dns_soa_edit', ['fields' => array_keys($input)], 502, 'linode_error');
            return response()->json(['message' => self::DNS_GENERIC_ERROR], 422);
        }
        $meta = (array) $dom->meta;
        $meta['soa_email'] = $d['soa_email'] ?? $clean['soa_email'] ?? ($meta['soa_email'] ?? null);
        $meta['ttl_sec'] = $d['ttl_sec'] ?? $clean['ttl_sec'] ?? ($meta['ttl_sec'] ?? null);
        $dom->meta = $meta;
        $dom->save();
        $this->dnsAudit($request, $srv, $dom, 'portal.dns_soa_edit', ['changed' => $clean]);
        return response()->json(['data' => $this->soaFacts($d + $clean, $dom), 'message' => 'SOA updated.']);
    }

    public function dnsRecordStore(Request $request, string $server, string $domainResource): JsonResponse
    {
        $input = $request->validate(LinodeService::RECORD_INPUT_RULES);
        [$srv, $dom, $svc] = $this->dnsContext($request, $server, $domainResource, true);
        if ($limited = $this->dnsLimited($request, $srv)) return $limited;
        try {
            if (count($svc->listRecords($dom->remote_id)) >= self::MAX_RECORDS_PER_DOMAIN) {
                return response()->json(['message' => 'This domain has reached the limit of ' . self::MAX_RECORDS_PER_DOMAIN . ' records. Use "Request server support".'], 422);
            }
            $rec = $svc->createRecord($dom->remote_id, $input);
        } catch (\InvalidArgumentException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        } catch (\Throwable $e) {
            $this->dnsAudit($request, $srv, $dom, 'portal.dns_record_add', ['record_type' => strtoupper((string) $input['type']), 'record_name' => $input['name'] ?? ''], 502, 'linode_error');
            return response()->json(['message' => self::DNS_GENERIC_ERROR], 422);
        }
        $this->dnsAudit($request, $srv, $dom, 'portal.dns_record_add', ['record_type' => $rec['type'] ?? strtoupper((string) $input['type']), 'record_name' => $rec['name'] ?? ($input['name'] ?? '')], 201);
        return response()->json(['data' => $this->safeRecord($rec), 'message' => 'Record added.'], 201);
    }

    public function dnsRecordUpdate(Request $request, string $server, string $domainResource, string $recordId): JsonResponse
    {
        $input = $request->validate(LinodeService::RECORD_INPUT_RULES);
        abort_unless(ctype_digit($recordId), 404, 'Not found');
        [$srv, $dom, $svc] = $this->dnsContext($request, $server, $domainResource, true);
        if ($limited = $this->dnsLimited($request, $srv)) return $limited;
        try {
            $rec = $svc->updateRecord($dom->remote_id, $recordId, $input);
        } catch (\InvalidArgumentException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        } catch (\Throwable $e) {
            $this->dnsAudit($request, $srv, $dom, 'portal.dns_record_edit', ['record_type' => strtoupper((string) $input['type']), 'record_name' => $input['name'] ?? ''], 502, 'linode_error');
            return response()->json(['message' => self::DNS_GENERIC_ERROR], 422);
        }
        $this->dnsAudit($request, $srv, $dom, 'portal.dns_record_edit', ['record_type' => $rec['type'] ?? strtoupper((string) $input['type']), 'record_name' => $rec['name'] ?? ($input['name'] ?? '')]);
        return response()->json(['data' => $this->safeRecord($rec), 'message' => 'Record updated.']);
    }

    /** (Re)create the standard A + www records pointing at this server. Idempotent: identical records are skipped. */
    public function dnsPointToServer(Request $request, string $server, string $domainResource): JsonResponse
    {
        [$srv, $dom, $svc] = $this->dnsContext($request, $server, $domainResource, true);
        $ip = $srv->ipv4[0] ?? null;
        if (!$ip) return response()->json(['message' => 'This server has no IP address right now. Use "Request server support".'], 422);
        if ($limited = $this->dnsLimited($request, $srv)) return $limited;
        try {
            if (count($svc->listRecords($dom->remote_id)) >= self::MAX_RECORDS_PER_DOMAIN) {
                return response()->json(['message' => 'This domain has reached the limit of ' . self::MAX_RECORDS_PER_DOMAIN . ' records. Use "Request server support".'], 422);
            }
            $created = $svc->createStandardWebRecords($dom->remote_id, $ip);
        } catch (\InvalidArgumentException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        } catch (\Throwable $e) {
            $this->dnsAudit($request, $srv, $dom, 'portal.dns_point_to_server', [], 502, 'linode_error');
            return response()->json(['message' => self::DNS_GENERIC_ERROR], 422);
        }
        $this->dnsAudit($request, $srv, $dom, 'portal.dns_point_to_server', ['records_created' => count($created)]);
        return response()->json(['message' => count($created) ? 'A and www records now point to this server.' : 'Records already point to this server.', 'data' => ['created' => count($created)]]);
    }

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

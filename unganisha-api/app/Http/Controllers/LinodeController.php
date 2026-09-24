<?php

namespace App\Http\Controllers;

use App\Exceptions\LinodeApiException;
use App\Models\Client;
use App\Models\ClientSubscription;
use App\Models\Domain;
use App\Models\LinodeAccount;
use App\Models\LinodeAuditLog;
use App\Models\LinodeResource;
use App\Models\RecurringInvoiceLog;
use App\Services\Linode\DnsMapping;
use App\Services\Linode\LinodeBilling;
use App\Services\Linode\LinodeService;
use App\Services\Registrar\NameserverService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Tenant Linode integration. Every query goes through tenant-scoped models
 * (BelongsToTenant) so tenant B can never see tenant A's accounts/resources.
 * The token is write-only: it is never included in any response.
 */
class LinodeController extends Controller
{
    // ── accounts ──

    public function accounts(): JsonResponse
    {
        return response()->json(['data' => LinodeAccount::orderBy('label')->get()->map->toSafeArray()]);
    }

    public function storeAccount(Request $request): JsonResponse
    {
        $data = $request->validate([
            'label'     => 'required|string|max:100',
            'token'     => ['required', 'string', 'min:20', 'max:512', 'regex:/^\S+$/'],
            'soa_email' => 'nullable|email|max:255',
        ]);

        $account = new LinodeAccount([
            'label' => $data['label'], 'token' => $data['token'], 'token_hint' => substr($data['token'], -4),
            'soa_email' => $data['soa_email'] ?? auth()->user()->email, 'status' => 'active',
        ]);
        $account->tenant_id = auth()->user()->tenant_id;

        try {
            $check = (new LinodeService($account))->verifyToken();
        } catch (LinodeApiException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }
        if ($check['status'] === 'invalid') {
            return response()->json(['message' => $check['message']], 422);
        }
        $account->status_message = $check['message'];
        $account->last_verified_at = now();
        $account->save();
        $this->audit($account, 'account.create', $account->label);

        return response()->json(['data' => $account->toSafeArray(), 'message' => $check['message'] ?? 'Linode account connected.'], 201);
    }

    public function updateAccount(Request $request, LinodeAccount $account): JsonResponse
    {
        $data = $request->validate([
            'label'     => 'sometimes|required|string|max:100',
            'token'     => ['nullable', 'string', 'min:20', 'max:512', 'regex:/^\S+$/'],
            'soa_email' => 'nullable|email|max:255',
        ]);

        $rotated = !empty($data['token']);
        if ($rotated) {
            $probe = new LinodeAccount(['token' => $data['token']]);
            $probe->tenant_id = $account->tenant_id;
            try {
                $check = (new LinodeService($probe))->verifyToken();
            } catch (LinodeApiException $e) {
                return response()->json(['message' => $e->getMessage()], 422);
            }
            if ($check['status'] === 'invalid') {
                return response()->json(['message' => $check['message']], 422);
            }
            $account->token = $data['token'];
            $account->token_hint = substr($data['token'], -4);
            $account->status = 'active';
            $account->status_message = $check['message'];
            $account->last_verified_at = now();
        }
        if (isset($data['label'])) $account->label = $data['label'];
        if (array_key_exists('soa_email', $data)) $account->soa_email = $data['soa_email'];
        $account->save();
        $this->audit($account, $rotated ? 'account.rotate_token' : 'account.update', $account->label);

        return response()->json(['data' => $account->toSafeArray(), 'message' => 'Saved.']);
    }

    public function destroyAccount(LinodeAccount $account): JsonResponse
    {
        $this->audit($account, 'account.delete', $account->label);
        // Only our local cache and stored token are removed; nothing is deleted at Linode.
        LinodeResource::where('linode_account_id', $account->id)->delete();
        $account->delete();

        return response()->json(['message' => 'Linode account removed from MoBilling. Nothing was deleted at Linode.']);
    }

    public function verifyAccount(LinodeAccount $account): JsonResponse
    {
        try {
            $check = (new LinodeService($account))->verifyToken();
        } catch (LinodeApiException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }
        $account->update(['status' => $check['status'], 'status_message' => $check['message'], 'last_verified_at' => now()]);

        return response()->json(['data' => $account->toSafeArray(), 'message' => $check['message'] ?? 'Token is valid.']);
    }

    public function sync(LinodeAccount $account): JsonResponse
    {
        $svc = new LinodeService($account);
        try {
            $instances = $svc->listInstances();
            $domains = $svc->listDomains();
        } catch (LinodeApiException $e) {
            if ($e->httpStatus === 401) {
                $account->update(['status' => 'invalid', 'status_message' => $e->getMessage()]);
            }
            return response()->json(['message' => $e->getMessage()], 422);
        }

        $now = now();
        $seen = ['instance' => [], 'domain' => []];

        foreach ($instances as $i) {
            $seen['instance'][] = (string) $i['id'];
            LinodeResource::updateOrCreate(
                ['linode_account_id' => $account->id, 'type' => 'instance', 'remote_id' => (string) $i['id']],
                [
                    'tenant_id' => $account->tenant_id,
                    'label' => $i['label'] ?? (string) $i['id'], 'status' => $i['status'] ?? null,
                    'region' => $i['region'] ?? null, 'plan' => $i['type'] ?? null,
                    'ipv4' => $i['ipv4'] ?? [], 'ipv6' => $i['ipv6'] ?? null, 'tags' => $i['tags'] ?? [],
                    'meta' => ['image' => $i['image'] ?? null, 'specs' => $i['specs'] ?? null, 'created' => $i['created'] ?? null],
                    'synced_at' => $now,
                ]
            );
        }

        foreach ($domains as $d) {
            $name = strtolower($d['domain'] ?? '');
            $seen['domain'][] = (string) $d['id'];
            $ours = Domain::where('name', $name)->value('id');
            $prevDns = LinodeResource::where('linode_account_id', $account->id)->where('type', 'domain')->where('remote_id', (string) $d['id'])->first()?->meta['dns'] ?? null;
            LinodeResource::updateOrCreate(
                ['linode_account_id' => $account->id, 'type' => 'domain', 'remote_id' => (string) $d['id']],
                [
                    'tenant_id' => $account->tenant_id,
                    'label' => $name, 'status' => $d['status'] ?? null,
                    'meta' => ['type' => $d['type'] ?? null, 'soa_email' => $d['soa_email'] ?? null, 'ttl_sec' => $d['ttl_sec'] ?? null] + ($prevDns ? ['dns' => $prevDns] : []),
                    'domain_id' => $ours, 'synced_at' => $now,
                ]
            );
        }

        $gone = 0;
        foreach (['instance', 'domain'] as $type) {
            $gone += LinodeResource::where('linode_account_id', $account->id)->where('type', $type)
                ->whereNotIn('remote_id', $seen[$type] ?: ['-'])->where(fn ($q) => $q->whereNull('status')->orWhere('status', '!=', 'gone'))
                ->update(['status' => 'gone', 'synced_at' => $now]);
        }

        $account->update(['last_synced_at' => $now, 'status' => 'active', 'last_verified_at' => $now]);
        $this->audit($account, 'account.sync', $account->label, ['instances' => count($instances), 'domains' => count($domains), 'gone' => $gone]);

        return response()->json([
            'data' => $account->toSafeArray(),
            'message' => 'Synced ' . count($instances) . ' server(s) and ' . count($domains) . ' domain(s)' . ($gone ? "; $gone no longer exist at Linode." : '.'),
        ]);
    }

    // ── read cache ──

    public function servers(): JsonResponse
    {
        $rows = LinodeResource::with(['account:id,label,last_synced_at', 'client:id,name'])->where('type', 'instance')->orderBy('label')->get();
        $domains = $this->domainRows();
        $byServer = [];
        foreach ($domains as $d) {
            foreach ($d['dns']['servers'] as $srv) $byServer[$srv['id']][] = $d;
        }

        // Billing summary per server (one batched query each; no per-row N+1).
        $subs = ClientSubscription::with('productService:id,name,price,billing_cycle')
            ->whereIn('id', $rows->pluck('client_subscription_id')->filter())->get()->keyBy('id');
        $logs = RecurringInvoiceLog::with('document:id,document_number,status,due_date,total')
            ->whereIn('client_subscription_id', $subs->keys())->whereNotNull('document_id')
            ->orderByDesc('invoice_created_at')->get()->unique('client_subscription_id')->keyBy('client_subscription_id');
        $billing = app(LinodeBilling::class);

        return response()->json(['data' => $rows->map(function ($r) use ($byServer, $subs, $logs, $billing) {
            $a = $this->resourceArray($r);
            $a['subscription'] = $billing->summary($subs->get($r->client_subscription_id), $logs->get($r->client_subscription_id));
            $mine = $byServer[$r->id] ?? [];
            $a['domain_count'] = count($mine);
            $a['domains'] = array_map(fn ($d) => ['id' => $d['id'], 'label' => $d['label']], $mine);
            // Suggestion only (never applied): every domain on this server belongs to the same client.
            $a['suggested_client'] = null;
            if (!$r->client_id && $mine) {
                $ids = array_unique(array_map(fn ($d) => $d['client_id'] ?? $d['suggested_client']['id'] ?? null, $mine));
                if (count($ids) === 1 && $ids[0]) {
                    $name = $mine[0]['client_name'] ?? $mine[0]['suggested_client']['name'] ?? null;
                    $a['suggested_client'] = ['id' => $ids[0], 'name' => $name, 'domains' => count($mine)];
                }
            }
            return $a;
        })]);
    }

    public function domains(): JsonResponse
    {
        $rows = $this->domainRows();
        $fetched = collect($rows)->pluck('dns.fetched_at')->filter()->max();

        return response()->json(['data' => $rows, 'dns_last_refreshed' => $fetched]);
    }

    /** Domain resources with our-domain link, DNS mapping (matched against CURRENT instances) and client suggestion. */
    private function domainRows(): array
    {
        $rows = LinodeResource::with(['account:id,label,last_synced_at', 'client:id,name'])->where('type', 'domain')->orderBy('label')->get();
        $ours = Domain::whereIn('id', $rows->pluck('domain_id')->filter())->get()->keyBy('id');
        $clientNames = Client::whereIn('id', $ours->pluck('client_id')->filter())->pluck('name', 'id');
        $instances = LinodeResource::where('type', 'instance')->where(fn ($q) => $q->whereNull('status')->orWhere('status', '!=', 'gone'))->get();
        $ipIndex = DnsMapping::buildIpIndex($instances->map(fn ($i) => ['id' => $i->id, 'ipv4' => $i->ipv4 ?? [], 'ipv6' => $i->ipv6])->all());
        $labels = $instances->pluck('label', 'id');

        return $rows->map(function ($r) use ($ours, $clientNames, $ipIndex, $labels) {
            $a = $this->resourceArray($r);
            $d = $r->domain_id ? $ours->get($r->domain_id) : null;
            $a['our_domain'] = $d ? [
                'id' => $d->id, 'status' => $d->status,
                'can_set_nameservers' => $this->canDelegate($d),
            ] : null;
            $a['dns'] = $this->dnsView($r->meta['dns'] ?? null, $ipIndex, $labels);
            $a['suggested_client'] = null;
            if (!$r->client_id && $d && $d->client_id && isset($clientNames[$d->client_id])) {
                $a['suggested_client'] = ['id' => $d->client_id, 'name' => $clientNames[$d->client_id]];
            }
            return $a;
        })->all();
    }

    private function dnsView(?array $dns, array $ipIndex, $labels): array
    {
        $empty = ['status' => 'unknown', 'apex_ips' => [], 'www_ips' => [], 'external_ips' => [], 'servers' => [], 'fetched_at' => null, 'error' => $dns['error'] ?? null];
        if (!$dns || empty($dns['fetched_at'])) return $empty;

        $m = DnsMapping::match($dns['apex_ips'] ?? [], $dns['www_ips'] ?? [], $ipIndex);
        $servers = array_map(fn ($id) => [
            'id' => $id, 'label' => $labels[$id] ?? '?',
            'apex' => in_array($id, $m['apex_instance_ids'], true), 'www' => in_array($id, $m['www_instance_ids'], true),
        ], $m['instance_ids']);

        return [
            'status' => $m['status'], 'apex_ips' => $dns['apex_ips'] ?? [], 'www_ips' => $dns['www_ips'] ?? [],
            'external_ips' => $m['external_ips'], 'servers' => $servers, 'fetched_at' => $dns['fetched_at'], 'error' => $dns['error'] ?? null,
        ];
    }

    /**
     * Read-only DNS lookups (GET records) for one batch of this account's domains and store where each
     * domain points. Batched so the UI can show progress and no request runs long; the service paces
     * paginated GETs (<=~170/min, Linode allows 200/min) and honours 429 Retry-After. A failing domain
     * never aborts the batch (except an invalid/forbidden token, which would fail every domain).
     */
    public function refreshDns(Request $request, LinodeAccount $account): JsonResponse
    {
        $data = $request->validate(['offset' => 'nullable|integer|min:0', 'limit' => 'nullable|integer|min:1|max:20']);
        $offset = (int) ($data['offset'] ?? 0);
        $limit = (int) ($data['limit'] ?? 10);

        $base = LinodeResource::where('linode_account_id', $account->id)->where('type', 'domain')
            ->where(fn ($q) => $q->whereNull('status')->orWhere('status', '!=', 'gone'));
        $total = (clone $base)->count();
        $batch = $base->orderBy('label')->skip($offset)->take($limit)->get();

        // instances of ALL the tenant's accounts
        $instances = LinodeResource::where('type', 'instance')->where(fn ($q) => $q->whereNull('status')->orWhere('status', '!=', 'gone'))->get();
        $ipIndex = DnsMapping::buildIpIndex($instances->map(fn ($i) => ['id' => $i->id, 'ipv4' => $i->ipv4 ?? [], 'ipv6' => $i->ipv6])->all());
        $svc = new LinodeService($account);
        $ok = 0;
        $failed = [];

        foreach ($batch as $res) {
            $meta = $res->meta ?? [];
            try {
                $addr = DnsMapping::extractAddresses($svc->listRecords($res->remote_id));
                $m = DnsMapping::match($addr['apex_ips'], $addr['www_ips'], $ipIndex);
                $meta['dns'] = $addr + [
                    'status' => $m['status'], 'points_to_instance_ids' => $m['instance_ids'],
                    'points_to_labels' => $instances->whereIn('id', $m['instance_ids'])->pluck('label')->values()->all(),
                    'external_ips' => $m['external_ips'], 'fetched_at' => now()->toIso8601String(), 'error' => null,
                ];
                $ok++;
            } catch (LinodeApiException $e) {
                if ($e->httpStatus === 401 || $e->httpStatus === 403) {
                    if ($e->httpStatus === 401) $account->update(['status' => 'invalid', 'status_message' => $e->getMessage()]);
                    return response()->json(['message' => $e->getMessage()], 422);
                }
                $meta['dns'] = ($meta['dns'] ?? []) + ['apex_ips' => [], 'www_ips' => []];
                $meta['dns']['error'] = mb_substr($e->getMessage(), 0, 250);
                $failed[] = ['domain' => $res->label, 'error' => $meta['dns']['error']];
            } catch (\Throwable $e) {
                $meta['dns'] = ($meta['dns'] ?? []) + ['apex_ips' => [], 'www_ips' => []];
                $meta['dns']['error'] = 'Unexpected error while reading DNS records.';
                $failed[] = ['domain' => $res->label, 'error' => $meta['dns']['error']];
            }
            $res->meta = $meta;
            $res->save();
        }

        $next = $offset + $batch->count();

        return response()->json([
            'processed' => $batch->count(), 'ok' => $ok, 'failed' => $failed, 'total' => $total,
            'next_offset' => $next < $total && $batch->count() > 0 ? $next : null,
        ]);
    }

    /** Fill the client of UNMAPPED domain resources from our own domains table. Never overwrites. */
    public function autoMapClients(Request $request): JsonResponse
    {
        $data = $request->validate(['confirm' => 'accepted', 'ids' => 'nullable|array', 'ids.*' => 'string']);
        $q = LinodeResource::with('account')->where('type', 'domain')->whereNull('client_id')->whereNotNull('domain_id');
        if (!empty($data['ids'])) $q->whereIn('id', $data['ids']);
        $rows = $q->get();
        $ours = Domain::whereIn('id', $rows->pluck('domain_id'))->whereNotNull('client_id')->get()->keyBy('id');
        $valid = Client::whereIn('id', $ours->pluck('client_id'))->pluck('name', 'id');

        $mapped = [];
        foreach ($rows as $r) {
            $cid = $ours->get($r->domain_id)?->client_id;
            if (!$cid || !isset($valid[$cid])) continue;
            // conditional update: cannot clobber a mapping made since the read
            $n = LinodeResource::where('id', $r->id)->whereNull('client_id')->update(['client_id' => $cid]);
            if (!$n) continue;
            $mapped[] = ['id' => $r->id, 'domain' => $r->label, 'client' => $valid[$cid]];
            if ($r->account) $this->audit($r->account, 'resource.map', $r->label, ['client_id' => $cid, 'auto' => true]);
        }

        return response()->json(['mapped' => $mapped, 'message' => count($mapped) . ' domain(s) mapped to their clients.']);
    }

    /** Live DNS lookup: are the domain's public NS records Linode's? (bounded, best-effort) */
    public function checkNameservers(LinodeResource $resource): JsonResponse
    {
        abort_unless($resource->type === 'domain', 404);
        $found = [];
        try {
            foreach (@dns_get_record($resource->label, DNS_NS) ?: [] as $rec) {
                $found[] = strtolower(rtrim($rec['target'] ?? '', '.'));
            }
        } catch (\Throwable $e) {
        }
        $ok = $found && count(array_diff($found, LinodeService::NAMESERVERS)) === 0;

        return response()->json(['data' => ['pointing_to_linode' => (bool) $ok, 'nameservers' => $found, 'expected' => LinodeService::NAMESERVERS]]);
    }

    // ── add domain ──

    public function storeDomain(Request $request): JsonResponse
    {
        $data = $request->validate([
            'account_id' => 'required|string',
            'domain'     => 'required|string|max:253',
            'soa_email'  => 'nullable|email|max:255',
            'ttl'        => 'nullable|integer',
            'server_id'  => 'nullable|string',
        ]);
        $account = LinodeAccount::findOrFail($data['account_id']);
        if ($account->status !== 'active') {
            return response()->json(['message' => 'This Linode account token is not valid. Rotate the token first.'], 422);
        }

        try {
            $domain = LinodeService::validateDomainName($data['domain']);
            $ttl = isset($data['ttl']) ? LinodeService::validateTtl($data['ttl']) : null;
        } catch (\InvalidArgumentException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        $server = null;
        if (!empty($data['server_id'])) {
            $server = LinodeResource::where('type', 'instance')->where('linode_account_id', $account->id)
                ->where('id', $data['server_id'])->where('status', '!=', 'gone')->first();
            if (!$server) return response()->json(['message' => 'Chosen server was not found in this Linode account.'], 422);
            if (empty($server->ipv4[0])) return response()->json(['message' => 'Chosen server has no IPv4 address.'], 422);
        }

        if (LinodeResource::where('type', 'domain')->where('label', $domain)->where('status', '!=', 'gone')->exists()) {
            return response()->json(['message' => "$domain is already added to Linode (it exists in your synced domains)."], 422);
        }

        $svc = new LinodeService($account);
        try {
            $created = $svc->createDomain($domain, $data['soa_email'] ?? $account->soa_email ?? auth()->user()->email, $ttl);
        } catch (\InvalidArgumentException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        } catch (LinodeApiException $e) {
            $msg = $e->getMessage();
            if ($e->httpStatus === 400 && stripos($msg, 'already exists') !== false) {
                $msg = "$domain already exists on Linode (possibly in another Linode account, since domain names are unique across Linode). $msg";
            }
            return response()->json(['message' => $msg], 422);
        }

        $resource = LinodeResource::updateOrCreate(
            ['linode_account_id' => $account->id, 'type' => 'domain', 'remote_id' => (string) $created['id']],
            [
                'tenant_id' => $account->tenant_id, 'label' => $domain, 'status' => $created['status'] ?? 'active',
                'meta' => ['type' => 'master', 'soa_email' => $created['soa_email'] ?? null, 'ttl_sec' => $created['ttl_sec'] ?? null],
                'domain_id' => Domain::where('name', $domain)->value('id'), 'synced_at' => now(),
            ]
        );

        $recordsCreated = 0;
        $warning = null;
        if ($server) {
            try {
                $recordsCreated = count($svc->createStandardWebRecords($created['id'], $server->ipv4[0]));
            } catch (\InvalidArgumentException | LinodeApiException $e) {
                $warning = 'Domain created, but adding the A records failed: ' . $e->getMessage() . ' You can add them from the Records drawer.';
            }
        }

        return response()->json([
            'data' => $this->resourceArray($resource->load('account:id,label,last_synced_at')) + [
                'records_created' => $recordsCreated,
                'nameservers' => LinodeService::NAMESERVERS,
                'note' => "Set these nameservers at your domain registrar. Until you do, DNS records here will not take effect. Changes can take up to a few hours to propagate.",
                'can_set_nameservers' => ($d = $resource->domain_id ? Domain::find($resource->domain_id) : null) ? $this->canDelegate($d) : false,
            ],
            'message' => $warning ?? "Domain $domain added to Linode.",
        ], 201);
    }

    /** Hand the nameserver change to the EXISTING registrar logic — only for our active .tz domains, and only with confirm=true. */
    public function setNameservers(Request $request, LinodeResource $resource): JsonResponse
    {
        abort_unless($resource->type === 'domain', 404);
        $request->validate(['confirm' => 'required|accepted']);
        $domain = $resource->domain_id ? Domain::find($resource->domain_id) : null;
        if (!$domain || !$this->canDelegate($domain)) {
            return response()->json(['message' => 'This domain is not an active .tz domain registered through MoBilling. Set the nameservers at your registrar instead.'], 422);
        }
        try {
            $result = app(NameserverService::class)->update($domain, LinodeService::NAMESERVERS, ['by_user' => auth()->id()]);
        } catch (\App\Exceptions\RegistrarApiException $e) {
            return response()->json(['message' => 'Registry error: ' . $e->getMessage()], 422);
        } catch (\RuntimeException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }
        $this->audit($resource->account, 'domain.set_nameservers', $resource->label, ['changed' => $result['changed']]);

        return response()->json(['message' => $result['changed']
            ? 'Nameservers updated at the registry. DNS changes can take up to a few hours to propagate.'
            : 'No changes - the domain already uses these nameservers.']);
    }

    // ── records ──

    public function records(LinodeResource $resource): JsonResponse
    {
        return $this->withDomain($resource, fn (LinodeService $s) => ['data' => array_map(fn ($r) => $r + ['locked' => in_array($r['type'] ?? '', ['NS', 'SOA'], true)], $s->listRecords($resource->remote_id))]);
    }

    public function storeRecord(Request $request, LinodeResource $resource): JsonResponse
    {
        return $this->withDomain($resource, fn (LinodeService $s) => ['data' => $s->createRecord($resource->remote_id, $this->recordInput($request)), 'message' => 'Record added.'], 201);
    }

    public function updateRecord(Request $request, LinodeResource $resource, string $recordId): JsonResponse
    {
        return $this->withDomain($resource, fn (LinodeService $s) => ['data' => $s->updateRecord($resource->remote_id, $recordId, $this->recordInput($request)), 'message' => 'Record updated.']);
    }

    public function destroyRecord(LinodeResource $resource, string $recordId): JsonResponse
    {
        return $this->withDomain($resource, function (LinodeService $s) use ($resource, $recordId) {
            $s->deleteRecord($resource->remote_id, $recordId);
            return ['message' => 'Record deleted.'];
        });
    }

    // ── mapping (phase 2 groundwork) ──

    public function map(Request $request, LinodeResource $resource): JsonResponse
    {
        $data = $request->validate(['client_id' => 'nullable|string', 'client_subscription_id' => 'nullable|string']);
        $clientId = $data['client_id'] ?? null;
        $subId = $data['client_subscription_id'] ?? null;

        if ($clientId && !Client::where('id', $clientId)->exists()) {
            return response()->json(['message' => 'That client does not belong to your business.'], 422);
        }
        if ($subId) {
            $sub = ClientSubscription::where('id', $subId)->first();
            if (!$sub || ($clientId && $sub->client_id !== $clientId)) {
                return response()->json(['message' => 'That subscription does not belong to the selected client.'], 422);
            }
            $clientId = $clientId ?: $sub->client_id;
        }

        // A billed server keeps its subscription link: re-mapping must not silently drop it or move
        // the server to a different client than the one being billed (use unlink-subscription first).
        $linked = !$request->has('client_subscription_id') && $resource->client_subscription_id
            ? ClientSubscription::where('id', $resource->client_subscription_id)->first() : null;
        if ($linked) {
            if ($clientId !== $linked->client_id) {
                return response()->json(['message' => 'This server is billed to another client. Unlink its subscription first.'], 422);
            }
            $subId = $linked->id;
        }

        $resource->update(['client_id' => $clientId, 'client_subscription_id' => $subId]);
        $this->audit($resource->account, 'resource.map', $resource->label, ['client_id' => $clientId, 'client_subscription_id' => $subId]);

        return response()->json(['data' => $this->resourceArray($resource->load(['account:id,label,last_synced_at', 'client:id,name'])), 'message' => 'Mapping saved.']);
    }

    // ── billing (server <-> subscription) ──

    /** Linode-type products and the actor's ability to create subscriptions. */
    public function billingProducts(): JsonResponse
    {
        return response()->json(['data' => app(LinodeBilling::class)->products()]);
    }

    /** A client's live subscriptions, for "Link existing subscription". */
    public function clientSubscriptions(Client $client): JsonResponse
    {
        $taken = LinodeResource::whereNotNull('client_subscription_id')->pluck('client_subscription_id')->all();
        $rows = ClientSubscription::with('productService:id,name,billing_cycle')
            ->where('client_id', $client->id)->whereIn('status', LinodeBilling::LIVE)->whereNotIn('id', $taken)->orderBy('label')->get();

        return response()->json(['data' => $rows->map(fn ($s) => [
            'id' => $s->id, 'label' => $s->label, 'product_name' => $s->productService?->name, 'status' => $s->status,
            'expire_date' => $s->expire_date?->toDateString(), 'billing_cycle' => $s->productService?->billing_cycle,
        ])]);
    }

    public function bill(Request $request, LinodeResource $resource): JsonResponse
    {
        $data = $request->validate([
            'client_id' => 'required|uuid', 'product_service_id' => 'required|uuid',
            'amount' => 'required|numeric|min:0.01|max:999999999', 'billing_cycle' => 'nullable|in:monthly,quarterly,half_yearly,yearly',
            'start_date' => 'required|date', 'expire_date' => 'nullable|date', 'label' => 'nullable|string|max:255',
            'mode' => 'required|in:paid_outside,invoice_now',
        ]);
        try {
            $res = app(LinodeBilling::class)->bill($resource, $data);
        } catch (\DomainException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return response()->json([
            'data' => ['subscription_id' => $res['subscription']->id, 'document_id' => $res['document']?->id, 'document_number' => $res['document']?->document_number],
            'message' => $res['document'] ? "Subscription created (pending payment) and invoice {$res['document']->document_number} issued." : 'Subscription created. No invoice was created; the next invoice is generated automatically before the renewal date.',
        ], 201);
    }

    public function linkSubscription(Request $request, LinodeResource $resource): JsonResponse
    {
        $data = $request->validate(['client_subscription_id' => 'required|uuid']);
        try {
            app(LinodeBilling::class)->link($resource, $data['client_subscription_id']);
        } catch (\DomainException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return response()->json(['message' => 'Subscription linked to this server.']);
    }

    public function unlinkSubscription(LinodeResource $resource): JsonResponse
    {
        app(LinodeBilling::class)->unlink($resource);

        return response()->json(['message' => 'Subscription unlinked. The subscription itself was not changed and nothing was changed at Linode.']);
    }

    // ── helpers ──

    private function recordInput(Request $request): array
    {
        return $request->validate([
            'type' => 'required|string|max:10', 'name' => 'nullable|string|max:253', 'target' => 'required|string|max:2000',
            'ttl_sec' => 'nullable|integer', 'priority' => 'nullable|integer', 'weight' => 'nullable|integer',
            'port' => 'nullable|integer', 'service' => 'nullable|string|max:60', 'protocol' => 'nullable|string|max:10', 'tag' => 'nullable|string|max:20',
        ]);
    }

    private function withDomain(LinodeResource $resource, callable $fn, int $okStatus = 200): JsonResponse
    {
        abort_unless($resource->type === 'domain', 404);
        $account = LinodeAccount::findOrFail($resource->linode_account_id);
        try {
            return response()->json($fn(new LinodeService($account)), $okStatus);
        } catch (\InvalidArgumentException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        } catch (LinodeApiException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }
    }

    private function canDelegate(Domain $d): bool
    {
        return $d->status === 'active' && !($d->meta['unmanaged'] ?? false) && str_ends_with($d->name, '.tz') && !empty($d->nsset_handle);
    }

    private function resourceArray(LinodeResource $r): array
    {
        return [
            'id' => $r->id, 'linode_account_id' => $r->linode_account_id, 'account_label' => $r->account?->label,
            'type' => $r->type, 'remote_id' => $r->remote_id, 'label' => $r->label, 'status' => $r->status,
            'region' => $r->region, 'plan' => $r->plan, 'ipv4' => $r->ipv4 ?? [], 'ipv6' => $r->ipv6, 'tags' => $r->tags ?? [],
            'meta' => $r->meta, 'client_id' => $r->client_id, 'client_name' => $r->client?->name,
            'client_subscription_id' => $r->client_subscription_id, 'domain_id' => $r->domain_id,
            'synced_at' => $r->synced_at, 'account_last_synced_at' => $r->account?->last_synced_at,
        ];
    }

    private function audit(LinodeAccount $account, string $action, ?string $target, array $extra = []): void
    {
        LinodeAuditLog::create([
            'tenant_id' => $account->tenant_id, 'user_id' => auth()->id(), 'linode_account_id' => $account->id,
            'action' => $action, 'target' => $target, 'request' => $extra ?: null, 'response_status' => 200,
        ]);
    }
}

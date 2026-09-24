<?php

namespace App\Http\Controllers;

use App\Exceptions\LinodeApiException;
use App\Models\Client;
use App\Models\ClientSubscription;
use App\Models\Domain;
use App\Models\LinodeAccount;
use App\Models\LinodeAuditLog;
use App\Models\LinodeResource;
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
            LinodeResource::updateOrCreate(
                ['linode_account_id' => $account->id, 'type' => 'domain', 'remote_id' => (string) $d['id']],
                [
                    'tenant_id' => $account->tenant_id,
                    'label' => $name, 'status' => $d['status'] ?? null,
                    'meta' => ['type' => $d['type'] ?? null, 'soa_email' => $d['soa_email'] ?? null, 'ttl_sec' => $d['ttl_sec'] ?? null],
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

        return response()->json(['data' => $rows->map(fn ($r) => $this->resourceArray($r))]);
    }

    public function domains(): JsonResponse
    {
        $rows = LinodeResource::with(['account:id,label,last_synced_at', 'client:id,name'])->where('type', 'domain')->orderBy('label')->get();
        $ours = Domain::whereIn('id', $rows->pluck('domain_id')->filter())->get()->keyBy('id');

        return response()->json(['data' => $rows->map(function ($r) use ($ours) {
            $a = $this->resourceArray($r);
            $d = $r->domain_id ? $ours->get($r->domain_id) : null;
            $a['our_domain'] = $d ? [
                'id' => $d->id, 'status' => $d->status,
                'can_set_nameservers' => $this->canDelegate($d),
            ] : null;
            return $a;
        })]);
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

        $resource->update(['client_id' => $clientId, 'client_subscription_id' => $subId]);
        $this->audit($resource->account, 'resource.map', $resource->label, ['client_id' => $clientId, 'client_subscription_id' => $subId]);

        return response()->json(['data' => $this->resourceArray($resource->load(['account:id,label,last_synced_at', 'client:id,name'])), 'message' => 'Mapping saved.']);
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

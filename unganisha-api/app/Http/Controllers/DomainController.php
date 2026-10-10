<?php

namespace App\Http\Controllers;

use App\Exceptions\RegistrarApiException;
use App\Exceptions\WhmApiException;
use App\Models\Client;
use App\Models\Document;
use App\Models\Domain;
use App\Models\DomainLog;
use App\Models\DomainTld;
use App\Models\Server;
use App\Services\DocumentNumberService;
use App\Services\Registrar\DomainRegistrarManager;
use App\Services\TznicWhoisService;
use App\Services\WhmService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;

class DomainController extends Controller
{
    public function __construct(private DomainRegistrarManager $registrar) {}

    /** Live availability check (read-only EPP). */
    public function check(Request $request)
    {
        $data = $request->validate(['name' => 'required|string|max:255|regex:/^[a-z0-9][a-z0-9.-]+\.[a-z.]{2,}$/i']);
        $name = strtolower($data['name']);

        $pricing = DomainTld::priceFor(auth()->user()->tenant_id, $this->tldOf($name));

        if (!$pricing && DomainTld::disabledNameCom(auth()->user()->tenant_id, $this->tldOf($name))) {
            return response()->json(['name' => $name, 'available' => null, 'reason' => sprintf(DomainTld::DISABLED_HINT, $this->tldOf($name)), 'offered' => false, 'pricing' => null]);
        }

        // No registrar driver can answer for this TLD (gTLDs — only .tz is
        // FRED-backed) — nothing to ask, so don't pretend to ask it.
        if ($pricing && $pricing->is_unmanaged && $pricing->registrar !== 'namecom') {
            $result = ['available' => true, 'reason' => 'Manually fulfilled — verify availability yourself before ordering; this was not checked against a live registry.'];
        } else {
            try {
                $result = $this->registrar->checkFor(auth()->user()->tenant_id, $name, $pricing);
            } catch (RegistrarApiException $e) {
                return response()->json(['message' => 'Registry check failed: ' . $e->getMessage()], 422);
            }
        }

        return response()->json([
            'name'      => $name,
            'available' => $result['available'],
            'reason'    => $result['reason'],
            'pricing'   => $pricing ? [
                'tld'            => $pricing->tld,
                'register_price' => (float) $pricing->register_price,
                'renew_price'    => (float) $pricing->renew_price,
                'transfer_price' => (float) $pricing->transfer_price,
                'years_min'      => $pricing->years_min,
                'years_max'      => $pricing->years_max,
            ] : null,
        ]);
    }

    /** Multi-TLD search: typed TLD first, then the popular on-sale TLDs (see DomainSuggestService). */
    public function suggest(Request $request, \App\Services\Registrar\DomainSuggestService $svc)
    {
        $data = $request->validate(\App\Services\Registrar\DomainSuggestService::rules());
        [$body, $status] = $svc->respond(auth()->user()->tenant_id, $data, 'staff');

        return response()->json($body, $status);
    }

    /**
     * WHOIS lookup for a .tz domain, straight from the TZNIC registry (port 43)
     * — the same data as whois.tznic.or.tz, in-house. Flags whether the domain
     * is sponsored by this tenant's own registrar.
     */
    public function whois(Request $request, TznicWhoisService $whois)
    {
        $data = $request->validate(['name' => 'required|string|max:255']);
        $domain = $whois->normalise($data['name']);

        if (!str_ends_with($domain, '.tz') || substr_count($domain, '.') < 1) {
            return response()->json(['message' => 'Enter a .tz domain, e.g. example.co.tz.'], 422);
        }

        $res = $whois->lookup($domain);

        $ours = $this->ourRegistrarHandle();
        $res['our_registrar'] = $ours;
        $res['is_ours'] = (bool) ($ours && $res['registrar'] && strcasecmp($res['registrar'], $ours) === 0);

        return response()->json(['data' => $res]);
    }

    public function index(Request $request)
    {
        $query = Domain::with(['client:id,name', 'registrarAccount:id,name'])
            ->orderByDesc('created_at');

        if ($request->filled('status')) $query->where('status', $request->status);
        if ($request->filled('client_id')) $query->where('client_id', $request->client_id);
        if ($request->filled('search')) {
            $query->where('name', 'like', "%{$request->search}%");
        }
        if ($request->boolean('expiring')) {
            $query->where('status', 'active')
                ->whereNotNull('expires_at')
                ->where('expires_at', '<=', now()->addDays(45))
                ->orderBy('expires_at');
        }
        if ($request->filled('ours')) {
            $handle = $this->ourRegistrarHandle();
            $request->boolean('ours')
                ? $query->where('meta->sponsoring_registrar', $handle)
                : $query->whereIn('status', ['active', 'expired'])->where(fn ($q) => $q
                    ->whereNull('meta->sponsoring_registrar')
                    ->orWhere('meta->sponsoring_registrar', '!=', $handle));
        }

        if ($request->filled('registrar')) {
            $linked = fn ($q) => $q->whereNotNull('meta->namecom')->orWhere('meta->registrar', 'namecom');
            match ($request->registrar) {
                'tznic'            => $query->where('name', 'like', '%.tz')->whereNull('meta->namecom'),
                'namecom'          => $query->where($linked),
                'unlinked'         => \App\Services\Registrar\DomainRegistrarLookup::scopeUnlinked($query),
                'namecom_unlinked' => \App\Services\Registrar\DomainRegistrarLookup::scopeUnlinked($query)->where('meta->registrar_lookup->kind', 'namecom'),
                'other'            => \App\Services\Registrar\DomainRegistrarLookup::scopeUnlinked($query)->where('meta->registrar_lookup->kind', 'other'),
                default            => null,
            };
        }

        $page = $query->paginate(min((int) $request->get('per_page', 20), 100));

        // Staff-only registrar view (never part of the portal responses).
        $accounts = \App\Models\NameComAccount::all();
        $labels = $accounts->mapWithKeys(fn ($a) => [$a->id => $a->displayLabel()])->all();
        $defaultId = ($accounts->firstWhere('is_default', true) ?? $accounts->first())?->id;
        $page->getCollection()->each(fn ($d) => $d->setAttribute('registrar_view', \App\Services\Registrar\DomainRegistrarLookup::view($d, $labels, $defaultId)));

        return response()->json(['data' => $page]);
    }

    /**
     * Every domain with an SSL check on file (SyncDomains' nightly SslProbe,
     * cached in meta), soonest-expiring first — no live probing here, this
     * just reads what the nightly sync already found.
     */
    public function sslExpiry(Request $request)
    {
        $query = Domain::with('client:id,name')
            ->where('meta->ssl_expires_at', '!=', null)
            ->whereIn('status', ['active', 'pending']);

        if ($request->filled('search')) {
            $s = $request->search;
            $query->where(fn ($q) => $q->where('name', 'like', "%{$s}%")
                ->orWhereHas('client', fn ($q2) => $q2->where('name', 'like', "%{$s}%")));
        }
        if ($request->boolean('invalid_only')) {
            $query->where('meta->ssl_valid', false);
        }

        $domains = $query->get();

        $rows = $domains->map(fn ($d) => [
            'id'             => $d->id,
            'name'           => $d->name,
            'client'         => $d->client ? ['id' => $d->client->id, 'name' => $d->client->name] : null,
            'ssl_valid'      => (bool) ($d->meta['ssl_valid'] ?? false),
            'ssl_expires_at' => $d->meta['ssl_expires_at'] ?? null,
            'ssl_issuer'     => $d->meta['ssl_issuer'] ?? null,
            'days_left'      => isset($d->meta['ssl_expires_at'])
                ? now()->startOfDay()->diffInDays(\Carbon\Carbon::parse($d->meta['ssl_expires_at'])->startOfDay(), false)
                : null,
        ])->sortBy('days_left')->values();

        return response()->json(['data' => $rows]);
    }

    /** Staff toggle: same policy as the portal — wallet-funded when ON. */
    public function setAutoRenew(Request $request, Domain $domain)
    {
        $data = $request->validate(['enabled' => 'required|boolean']);

        if ($data['enabled']) {
            if ($domain->meta['unmanaged'] ?? false) {
                return response()->json(['message' => 'Unmanaged gTLD — auto-renew is not available (renew manually at its registrar).'], 422);
            }
            if (!in_array($domain->status, ['active', 'expired'])) {
                return response()->json(['message' => 'Auto-renew is only available for active domains.'], 422);
            }
        }

        $domain->update(['auto_renew' => $data['enabled']]);

        return response()->json([
            'data'    => ['auto_renew' => $domain->auto_renew],
            'message' => $data['enabled']
                ? "Auto-renew ON for {$domain->name} — renewals are paid from the client's wallet balance."
                : "Auto-renew OFF for {$domain->name}.",
        ]);
    }

    /** Live nameserver list for a domain (registry truth). */
    public function nameservers(Domain $domain)
    {
        if (\App\Services\Registrar\NameComDomainService::isLinked($domain)) {
            try {
                $ns = app(\App\Services\Registrar\NameComDomainService::class)->nameservers($domain);
            } catch (\App\Exceptions\NameComApiException | RegistrarApiException $e) {
                return response()->json(['message' => 'Could not read nameservers from Name.com: ' . preg_replace('/^Registrar \S+ failed: /', '', $e->getMessage())], 422);
            }
            return response()->json(['data' => ['provider' => 'namecom', 'nsset' => null, 'nameservers' => $ns, 'shared_with' => 0, 'original_nameservers' => \App\Services\Registrar\NameComDomainService::original($domain)]]);
        }
        if (($domain->meta['unmanaged'] ?? false) || !str_ends_with($domain->name, '.tz')) {
            return response()->json(['message' => 'Nameservers for this domain are managed at its external registrar.'], 422);
        }
        if (!$domain->nsset_handle) {
            return response()->json(['data' => ['nsset' => null, 'nameservers' => [], 'shared_with' => 0]]);
        }

        try {
            return response()->json(['data' => app(\App\Services\Registrar\NameserverService::class)->list($domain)]);
        } catch (\App\Exceptions\RegistrarApiException) {
            return response()->json(['message' => 'Could not reach the registry — try again shortly.'], 422);
        }
    }

    /**
     * Change the domain's nameservers. NSsets are shared objects at the FRED
     * registry — if any other domain uses this one, we create a NEW nsset and
     * repoint only this domain; an exclusive nsset is updated in place.
     * All operations are free EPP calls (no registry credit).
     */
    public function updateNameservers(Request $request, Domain $domain)
    {
        if (\App\Services\Registrar\NameComDomainService::isLinked($domain)) {
            abort_unless(in_array($domain->status, ['active', 'expired']), 422, 'Domain is not active.');
            $data = $request->validate(['nameservers' => 'required|array|max:20', 'nameservers.*' => 'required|string|max:253']);
            try {
                $r = app(\App\Services\Registrar\NameComDomainService::class)->updateNameservers($domain, $data['nameservers'], ['by_user' => auth()->id()]);
            } catch (\InvalidArgumentException | \DomainException $e) {
                return response()->json(['message' => $e->getMessage()], 422);
            } catch (\App\Exceptions\NameComApiException | RegistrarApiException $e) {
                return response()->json(['message' => preg_replace('/^Registrar \S+ failed: /', '', $e->getMessage())], 422);
            }
            return response()->json([
                'data'    => ['provider' => 'namecom', 'nsset' => null, 'nameservers' => $r['nameservers']],
                'message' => $r['changed'] ? 'Nameservers updated at Name.com. DNS changes can take up to a few hours to propagate.' : 'No changes - those are already the nameservers.',
            ]);
        }
        abort_if(($domain->meta['unmanaged'] ?? false) || !str_ends_with($domain->name, '.tz'), 422,
            'Nameservers for this domain are managed at its external registrar.');
        abort_unless(in_array($domain->status, ['active', 'expired']), 422, 'Domain is not active at the registry.');
        abort_unless($domain->nsset_handle, 422, 'This domain has no nameserver set at the registry yet — contact TZNIC support.');

        $data = $request->validate([
            'nameservers'   => 'required|array|min:2|max:9',
            'nameservers.*' => ['required', 'string', 'max:253', 'distinct',
                'regex:/^(?=.{4,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$/i'],
        ]);
        try {
            $result = app(\App\Services\Registrar\NameserverService::class)
                ->update($domain, $data['nameservers'], ['by_user' => auth()->id()]);
        } catch (\App\Exceptions\RegistrarApiException $e) {
            return response()->json(['message' => 'Registry error: ' . $e->getMessage()], 422);
        } catch (\RuntimeException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        if (!$result['changed']) {
            return response()->json(['message' => 'No changes — those are already the nameservers.']);
        }

        return response()->json([
            'data'    => ['nsset' => $result['nsset'], 'nameservers' => $data['nameservers']],
            'message' => 'Nameservers updated at the registry. DNS changes can take up to a few hours to propagate.',
        ]);
    }

    /** Security alert to the registrant — the EPP code can move the domain away. */
    private function notifyAuthInfoRevealed(Domain $domain): void
    {
        try {
            $client = $domain->client()->withoutGlobalScopes()->first();
            $tenant = \App\Models\Tenant::withoutGlobalScopes()->find($domain->tenant_id);
            if ($client && $tenant && ($client->email || $client->phone)) {
                $client->notify(new \App\Notifications\DomainAuthInfoRevealedNotification($domain, $tenant));
            }
        } catch (\Throwable $e) {
            \Illuminate\Support\Facades\Log::warning('AuthInfo notice failed', ['error' => $e->getMessage()]);
        }
    }

    /** The platform registrar handle at the registry (e.g. REG-MOINFOTECH). */
    private function ourRegistrarHandle(): ?string
    {
        return \App\Models\RegistrarAccount::whereNull('tenant_id')
            ->where('is_active', true)->value('registrar_id');
    }

    /** Summary numbers for the Domains page dashboard strip. */
    /**
     * Prepaid registrar (TZNIC) credit balance per zone — real money the
     * registry draws for register/renew. Cached briefly (live external call).
     */
    public function registrarCredit(Request $request)
    {
        abort_if(
            (bool) \App\Models\Tenant::withoutGlobalScopes()->find(auth()->user()->tenant_id)?->is_wallet_gated,
            403,
            'Registrar credit is not available for this account.'
        );

        $threshold = (float) $request->get('threshold', 50000);

        $data = \Illuminate\Support\Facades\Cache::remember('registrar_credit', now()->addMinutes(5), function () {
            $account = \App\Models\RegistrarAccount::whereNull('tenant_id')->where('is_active', true)->first();
            if (!$account) {
                return ['ok' => false, 'zones' => []];
            }
            try {
                $zones = collect((new \App\Services\Registrar\FredHttpDriver($account))->credit())
                    ->map(fn ($c) => ['zone' => $c['zone'], 'credit' => (float) $c['credit']])
                    ->sortByDesc('credit')->values()->all();

                return ['ok' => true, 'zones' => $zones, 'checked_at' => now()->toISOString()];
            } catch (\Throwable $e) {
                return ['ok' => false, 'zones' => [], 'error' => $e->getMessage()];
            }
        });

        $funded = collect($data['zones'])->filter(fn ($z) => $z['credit'] > 0)->values();

        $pending = \App\Models\RegistrarCreditTransfer::where('status', 'pending')
            ->orderByDesc('created_at')->get()
            ->map(fn ($tf) => [
                'id' => $tf->id, 'from_zone' => $tf->from_zone, 'to_zone' => $tf->to_zone,
                'amount' => (float) $tf->amount, 'requested_by' => $tf->requested_by_name,
                'created_at' => $tf->created_at->toISOString(),
            ]);

        return response()->json(['data' => [
            'ok'          => $data['ok'] ?? false,
            'zones'       => $data['zones'] ?? [],
            'total'       => (float) $funded->sum('credit'),
            'funded_count'=> $funded->count(),
            // funded zones running low (below threshold) need a top-up
            'low'         => $funded->filter(fn ($z) => $z['credit'] < $threshold)->pluck('zone')->all(),
            'pending_transfers' => $pending,
            'checked_at'  => $data['checked_at'] ?? null,
            'error'       => $data['error'] ?? null,
        ]]);
    }

    /** Staff banner/filter counts: where non-.tz domains live, and when Name.com was last refreshed. */
    private function registrarSummary(): array
    {
        $unlinked = fn () => \App\Services\Registrar\DomainRegistrarLookup::scopeUnlinked(Domain::query());
        $linked = Domain::whereNotIn('status', ['cancelled', 'transferred_out'])
            ->where(fn ($q) => $q->whereNotNull('meta->namecom')->orWhere('meta->registrar', 'namecom'))->get(['id', 'meta']);
        $last = $linked->map(fn ($d) => $d->meta['namecom']['synced_at'] ?? null)->filter()->max();
        $unchecked = $unlinked()->get(['id', 'meta'])->filter(fn ($d) => !\App\Services\Registrar\DomainRegistrarLookup::isFresh($d))->count();
        return [
            'linked_namecom'    => $linked->count(),
            'unlinked_non_tz'   => $unlinked()->count(),
            'at_namecom_unlinked' => $unlinked()->where('meta->registrar_lookup->kind', 'namecom')->count(),
            'at_other'          => $unlinked()->where('meta->registrar_lookup->kind', 'other')->count(),
            'lookup_due'        => $unchecked,
            'last_synced_at'    => $last,
        ];
    }

    public function stats()
    {
        $byStatus = Domain::selectRaw('status, COUNT(*) as c')->groupBy('status')->pluck('c', 'status');

        $active = Domain::where('status', 'active');
        $handle = $this->ourRegistrarHandle();
        $live   = Domain::whereIn('status', ['active', 'expired']);

        return response()->json(['data' => [
            'total'          => (int) $byStatus->sum(),
            'active'         => (int) ($byStatus['active'] ?? 0),
            'pending'        => (int) ($byStatus['pending'] ?? 0),
            'expired'        => (int) ($byStatus['expired'] ?? 0),
            'cancelled'      => (int) ($byStatus['cancelled'] ?? 0),
            'failed'         => (int) ($byStatus['failed'] ?? 0),
            'expiring_soon'  => (clone $active)->whereNotNull('expires_at')
                ->where('expires_at', '<=', now()->addDays(45))->count(),
            'auto_renew'     => (clone $active)->where('auto_renew', true)->count(),
            // registry-confirmed sponsorship (set by domains:sync from EPP cl_id)
            'our_registrar'  => $handle,
            'registrar_summary' => $this->registrarSummary(),
            'ours'           => $handle ? (clone $live)->where('meta->sponsoring_registrar', $handle)->count() : 0,
            'external'       => $handle ? (clone $live)->where(fn ($q) => $q
                ->whereNull('meta->sponsoring_registrar')
                ->orWhere('meta->sponsoring_registrar', '!=', $handle))->count() : 0,
        ]]);
    }

    public function show(Domain $domain)
    {
        return response()->json([
            'data' => $domain->load(['client:id,name', 'registrarAccount:id,name', 'subscription:id,label,expire_date']),
        ]);
    }

    /**
     * Live, read-only facts for a Name.com domain (staff page). Never throws: a Name.com failure
     * comes back as `error` so the page still renders. Nothing here is stored or leaks credentials.
     */
    public function registrarInfo(Domain $domain)
    {
        if (!\App\Services\Registrar\NameComDomainService::isNameComDomain($domain)) {
            return response()->json(['data' => ['provider' => 'fred', 'label' => null, 'facts' => null, 'error' => null]]);
        }
        $svc = app(\App\Services\Registrar\NameComDomainService::class);
        $facts = null; $error = null;
        if (!\App\Services\Registrar\NameComDomainService::isLinked($domain)) {
            $error = 'This domain is not linked to a Name.com account yet.';
        } else {
            try {
                $facts = $svc->facts($domain);
            } catch (\App\Exceptions\NameComApiException | RegistrarApiException $e) {
                $error = 'Could not read from Name.com right now: ' . preg_replace('/^Registrar \S+ failed: /', '', $e->getMessage());
            }
        }
        return response()->json(['data' => [
            'provider' => 'namecom',
            'label'    => \App\Services\Registrar\NameComDomainService::accountLabel($domain),
            'linked'   => \App\Services\Registrar\NameComDomainService::isLinked($domain),
            'facts'    => $facts,
            'error'    => $error,
        ]]);
    }

    public function logs(Domain $domain)
    {
        return response()->json(['data' => $domain->logs()->limit(50)->get()]);
    }

    /**
     * Cross-domain register/renew history — a dated "statement" so staff can
     * cross-check registry topup spend against when domains actually went
     * out. DomainLog has no BelongsToTenant scope, so tenant_id is filtered
     * explicitly here. Price is whatever was actually invoiced for that
     * event (via meta.order_document_id / renewal_document_id, stashed on
     * the domain when the order/renewal was created) — not a guessed
     * wholesale cost, since no such figure is tracked for FRED/.tz domains.
     */
    public function activityLog(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;
        $actions = ['registered', 'renewed', 'namecom_registered', 'manual_register_confirmed', 'renewal_paid_manual_action_needed'];
        $registerActions = ['registered', 'namecom_registered', 'manual_register_confirmed'];

        $base = DomainLog::query()
            ->where('tenant_id', $tenantId)
            ->whereIn('action', $actions);

        if ($request->filled('date_from')) {
            $base->whereDate('created_at', '>=', $request->date_from);
        }
        if ($request->filled('date_to')) {
            $base->whereDate('created_at', '<=', $request->date_to);
        }
        if ($request->filled('search')) {
            $search = $request->search;
            $base->whereHas('domain', fn ($q) => $q->where('name', 'like', "%{$search}%")
                ->orWhereHas('client', fn ($q2) => $q2->where('name', 'like', "%{$search}%")));
        }
        if ($request->get('type') === 'register') {
            $base->whereIn('action', $registerActions);
        } elseif ($request->get('type') === 'renew') {
            $base->whereNotIn('action', $registerActions);
        }

        // Full filtered set (lightweight columns) drives the period summary —
        // it must reflect every matching row, not just the current page.
        $all = (clone $base)->get(['id', 'action', 'request']);
        $docIds = $all->map(fn ($log) => $log->request['document_id'] ?? null)->filter()->unique()->values();
        $totals = Document::withoutGlobalScopes()->whereIn('id', $docIds)->pluck('total', 'id');

        $summary = [
            'count_register' => $all->whereIn('action', $registerActions)->count(),
            'count_renew'    => $all->whereNotIn('action', $registerActions)->count(),
            'total_price'    => round($all->sum(fn ($log) => ($log->request['document_id'] ?? null) ? (float) ($totals[$log->request['document_id']] ?? 0) : 0), 2),
            'total_paid_usd' => round($all->where('action', 'namecom_registered')->sum(fn ($log) => (float) ($log->request['total_paid_usd'] ?? 0)), 2),
        ];

        $page = (clone $base)
            ->with(['domain:id,name,client_id', 'domain.client:id,name'])
            ->orderByDesc('created_at')
            ->paginate(min((int) $request->get('per_page', 20), 100));

        $page->getCollection()->transform(function (DomainLog $log) use ($totals, $registerActions) {
            $docId = $log->request['document_id'] ?? null;

            return [
                'id'         => $log->id,
                'domain'     => $log->domain?->name,
                'client'     => $log->domain?->client?->name,
                'type'       => in_array($log->action, $registerActions, true) ? 'register' : 'renew',
                'years'      => $log->request['years'] ?? null,
                'price'      => $docId && isset($totals[$docId]) ? (float) $totals[$docId] : null,
                'paid_usd'   => $log->action === 'namecom_registered' ? ($log->request['total_paid_usd'] ?? null) : null,
                'created_at' => $log->created_at,
            ];
        });

        return response()->json(['data' => $page, 'summary' => $summary]);
    }

    /**
     * On-demand version of the domains:sync command's per-domain logic, for
     * just one domain — e.g. one added via addExisting() that's missing
     * expiry/nameserver data until the nightly sync catches up (see
     * SyncDomains::handle(), which this mirrors).
     */
    public function sync(Domain $domain)
    {
        if (\App\Services\Registrar\NameComDomainService::isLinked($domain)) {
            return app(NameComController::class)->refresh($domain);
        }
        abort_if($domain->meta['unmanaged'] ?? false, 422, 'This domain is managed at its external registrar — nothing to sync here.');
        abort_unless(str_ends_with($domain->name, '.tz'), 422, 'Only .tz domains can be synced from the registry.');

        try {
            $info = $this->registrar->driverFor($domain->tenant_id, $domain->id)->info($domain->name);

            $expires = substr((string) ($info['ex_date'] ?? ''), 0, 10) ?: null;
            $status = $domain->status;
            if ($expires) {
                $status = \Carbon\Carbon::parse($expires)->isPast() ? 'expired' : 'active';
            }

            $domain->update([
                'status'            => $status,
                'registered_at'     => substr((string) ($info['cr_date'] ?? ''), 0, 10) ?: $domain->registered_at,
                'expires_at'        => $expires ?? $domain->expires_at,
                'registrant_handle' => $info['registrant'] ?? $domain->registrant_handle,
                'nsset_handle'      => $info['nsset'] ?? $domain->nsset_handle,
                'keyset_handle'     => $info['keyset'] ?? $domain->keyset_handle,
                'meta'              => array_merge($domain->meta ?? [], [
                    'last_synced_at'       => now()->toIso8601String(),
                    'sponsoring_registrar' => $info['cl_id'] ?? ($domain->meta['sponsoring_registrar'] ?? null),
                ], \App\Services\SslProbe::probe($domain->name)),
            ]);
        } catch (\Throwable $e) {
            // EPP 2303 = object does not exist: the registry purged it.
            if (str_contains($e->getMessage(), '2303')) {
                $domain->update([
                    'status' => 'cancelled',
                    'meta'   => array_merge($domain->meta ?? [], [
                        'registry_missing'  => true,
                        'closed_by_sync_at' => now()->toIso8601String(),
                    ]),
                ]);
                return response()->json(['message' => 'This domain no longer exists at the registry — marked cancelled.'], 422);
            }

            return response()->json(['message' => 'Sync failed: ' . $e->getMessage()], 422);
        }

        return response()->json([
            'data'    => $domain->fresh(),
            'message' => 'Synced from the registry.',
        ]);
    }

    /**
     * Record a domain that's already registered (elsewhere, or at TZNIC under
     * some other sponsor/import we never billed) — pure bookkeeping so it
     * shows up under a client for renewal tracking. No invoice, no EPP call;
     * "TZNIC" only marks it as one of ours for future nameserver/EPP actions,
     * it does NOT take over sponsorship at the registry.
     */
    public function addExisting(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'name'       => ['required', 'string', 'max:255', 'regex:/^[a-z0-9][a-z0-9.-]+\.[a-z.]{2,}$/i', Rule::unique('domains', 'name')->where(fn ($q) => $q->whereNotIn('status', ['cancelled', 'transferred_out']))],
            'client_id'  => ['required', 'uuid', Rule::exists('clients', 'id')->where('tenant_id', $tenantId)],
            'registrar'  => ['required', 'in:tznic,external'],
            'expires_at' => 'nullable|date',
            'notes'      => 'nullable|string|max:255',
        ]);

        $name = strtolower($data['name']);
        $isTznic = $data['registrar'] === 'tznic';

        $domain = Domain::reviveOrCreate([
            'tenant_id'            => $tenantId,
            'client_id'            => $data['client_id'],
            'registrar_account_id' => $isTznic ? $this->registrar->accountFor($tenantId)->id : null,
            'name'                 => $name,
            'status'               => 'active',
            'auto_renew'           => false,
            'expires_at'           => $data['expires_at'] ?? null,
            'meta'                 => array_filter([
                'unmanaged'         => !$isTznic,
                'added_existing'    => true,
                'external_notes'    => $data['notes'] ?? null,
            ]),
        ]);

        DomainLog::create([
            'tenant_id' => $tenantId,
            'domain_id' => $domain->id,
            'action'    => 'added_existing',
            'request'   => ['by_user' => auth()->id(), 'registrar' => $data['registrar']],
            'status'    => 'success',
        ]);

        return response()->json([
            'data'    => $domain->load('client:id,name'),
            'message' => "{$name} added" . ($isTznic ? '.' : ' as an externally-registered domain.'),
        ], 201);
    }

    /**
     * Order a registration or transfer-in: creates the pending Domain row and
     * its invoice. Nothing touches the registry here — the paid EPP call fires
     * from the payment hook (Workstream B3).
     */
    public function order(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'name'      => ['required', 'string', 'max:255', 'regex:/^[a-z0-9][a-z0-9.-]+\.[a-z.]{2,}$/i', Rule::unique('domains', 'name')->where(fn ($q) => $q->whereNotIn('status', ['cancelled', 'transferred_out']))],
            'client_id' => ['required', 'uuid', Rule::exists('clients', 'id')->where('tenant_id', $tenantId)],
            'years'     => 'required|integer|min:1|max:10',
            'action'    => 'required|in:register,transfer',
            'auth_info' => 'required_if:action,transfer|nullable|string|max:255',
        ]);

        $name    = strtolower($data['name']);
        $pricing = DomainTld::priceFor($tenantId, $this->tldOf($name));
        if (!$pricing && DomainTld::disabledNameCom($tenantId, $this->tldOf($name))) {
            return response()->json(['message' => sprintf(DomainTld::DISABLED_HINT, $this->tldOf($name))], 422);
        }
        if (!$pricing) {
            return response()->json(['message' => 'No pricing configured for .' . $this->tldOf($name) . ' — add it in Settings → Domains.'], 422);
        }
        if ($data['years'] < $pricing->years_min || $data['years'] > $pricing->years_max) {
            return response()->json(['message' => "Years must be between {$pricing->years_min} and {$pricing->years_max}."], 422);
        }

        // Registration orders must be for available names (read-only EPP
        // check) — skipped for unmanaged TLDs: no registrar driver exists to
        // ask, staff is responsible for confirming availability themselves
        // before ordering (see the advisory note check() already returns).
        $viaNameCom = $pricing->registrar === 'namecom';
        if ($viaNameCom && $data['action'] !== 'register') {
            return response()->json(['message' => "Transfers of .{$this->tldOf($name)} (Name.com) are not supported here - record it as an existing domain instead."], 422);
        }
        if ($data['action'] === 'register' && (!$pricing->is_unmanaged || $viaNameCom)) {
            try {
                $check = $this->registrar->checkFor($tenantId, $name, $pricing);
                if (!$check['available']) {
                    return response()->json(['message' => "{$name} is not available: " . ($check['reason'] ?? 'taken')], 422);
                }
            } catch (RegistrarApiException $e) {
                return response()->json(['message' => 'Registry check failed: ' . $e->getMessage()], 422);
            }
        }

        $unitPrice = $data['action'] === 'register' ? $pricing->register_price : $pricing->transfer_price;
        $total     = round($unitPrice * $data['years'], 2);

        $result = DB::transaction(function () use ($data, $name, $tenantId, $total, $unitPrice, $pricing, $viaNameCom) {
            $document = Document::create([
                'tenant_id'       => $tenantId,
                'client_id'       => $data['client_id'],
                'type'            => 'invoice',
                'document_number' => app(DocumentNumberService::class)->generate('invoice', $tenantId),
                'date'            => now()->toDateString(),
                'due_date'        => now()->addDays(7)->toDateString(),
                'subtotal'        => $total,
                'discount_amount' => 0,
                'tax_amount'      => 0,
                'total'           => $total,
                'status'          => 'sent',
                'notes'           => "Domain {$data['action']}: {$name} ({$data['years']} year(s))",
                'created_by'      => auth()->id(),
            ]);

            $document->items()->create([
                'item_type'   => 'service',
                'description' => ucfirst($data['action']) . " domain {$name} — {$data['years']} year(s)",
                'quantity'    => $data['years'],
                'price'       => $unitPrice,
                'tax_percent' => 0,
                'tax_amount'  => 0,
                'total'       => $total,
            ]);

            $domain = Domain::reviveOrCreate([
                'tenant_id'            => $tenantId,
                'client_id'            => $data['client_id'],
                'registrar_account_id' => $viaNameCom ? null : $this->registrar->accountFor($tenantId)->id,
                'name'                 => $name,
                'status'               => 'pending',
                // off by default — the client opts in via the portal
                'auto_renew'           => false,
                'epp_auth_info'        => $data['auth_info'] ?? null,
                'meta'                 => [
                    'pending_action'    => $data['action'],
                    'pending_years'     => $data['years'],
                    'order_document_id' => $document->id,
                    'unmanaged'         => $pricing->is_unmanaged,
                ] + ($viaNameCom ? ['registrar' => 'namecom', 'namecom_years' => (int) $data['years']] : []),
            ]);

            return [$domain, $document];
        });

        [$domain, $document] = $result;

        // Ping the client with the invoice (WhatsApp with Pay Now / email / SMS
        // per tenant settings). Best-effort — the order already exists.
        try {
            $document->loadMissing('client');
            if ($document->client && ($document->client->phone || $document->client->email)) {
                $document->client->notifyNow(new \App\Notifications\InvoiceSentNotification($document));
            }
        } catch (\Throwable $e) {
            report($e);
        }

        return response()->json([
            'data'     => $domain->load('client:id,name'),
            'document' => ['id' => $document->id, 'document_number' => $document->document_number, 'total' => $document->total],
            'message'  => $viaNameCom
                ? "Order created - invoice {$document->document_number}. Once it is paid the domain appears in the Name.com registration queue (Domains page) for you to register."
                : ($pricing->is_unmanaged
                ? "Order created — invoice {$document->document_number}. No registrar integration for .{$this->tldOf($name)}: once paid, {$data['action']} it yourself at your registrar, then mark it registered here."
                : "Order created — invoice {$document->document_number}. The domain will be {$data['action']}ed at the registry once the invoice is paid."),
        ], 201);
    }

    /** Manual renewal order: creates the renewal invoice (EPP renew fires on payment). */
    public function renew(Request $request, Domain $domain, \App\Services\Registrar\DomainBillingService $billing)
    {
        $data = $request->validate(['years' => 'required|integer|min:1|max:10']);

        try {
            $document = $billing->createRenewalInvoice($domain, $data['years'], auth()->id());
        } catch (\RuntimeException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        // Ping the client with the renewal invoice (WhatsApp with Pay Now /
        // email / SMS per tenant settings). Best-effort.
        try {
            $document->loadMissing('client');
            if ($document->client && ($document->client->phone || $document->client->email)) {
                $document->client->notifyNow(new \App\Notifications\InvoiceSentNotification($document));
            }
        } catch (\Throwable $e) {
            report($e);
        }

        return response()->json([
            'document' => ['id' => $document->id, 'document_number' => $document->document_number, 'total' => $document->total],
            'message'  => "Renewal invoice {$document->document_number} created — the registry renewal runs once it is paid.",
        ], 201);
    }

    /**
     * Re-attempt a failed register/transfer/renew — no new invoice, since the
     * client already paid for the original order. BaseDomainJob::guard()
     * only flips status to 'failed' on exception, before clearPending() runs,
     * so meta.pending_action/pending_years survive a failure untouched; this
     * just resets status back to 'pending' (satisfying each job's own
     * idempotency guard) and re-dispatches the same job DocumentObserver
     * would have on payment.
     */
    public function retry(Domain $domain)
    {
        if ($domain->status !== 'failed') {
            return response()->json(['message' => 'Only a failed domain action can be retried.'], 422);
        }

        $pendingAction = $domain->meta['pending_action'] ?? null;
        if (!$pendingAction) {
            return response()->json(['message' => 'No pending action recorded for this domain — nothing to retry.'], 422);
        }

        $domain->update(['status' => 'pending']);

        match ($pendingAction) {
            'register' => \App\Jobs\Domains\RegisterDomainJob::dispatch($domain),
            'transfer' => \App\Jobs\Domains\TransferDomainJob::dispatch($domain),
            'renew'    => \App\Jobs\Domains\RenewDomainJob::dispatch($domain),
            default    => null,
        };

        return response()->json([
            'data'    => $domain->fresh()->load('client:id,name'),
            'message' => "Retrying {$pendingAction} for {$domain->name}\u{2026}",
        ]);
    }

    /**
     * Staff confirms they've completed the registration themselves at the
     * gTLD's actual registrar (no driver here to do it automatically) —
     * records what really happened there and activates the domain.
     */
    public function confirmManual(Request $request, Domain $domain)
    {
        if (!($domain->meta['awaiting_manual_registration'] ?? false)) {
            return response()->json(['message' => 'This domain is not awaiting manual registration.'], 422);
        }

        $data = $request->validate([
            'registered_at' => 'required|date',
            'expires_at'    => 'required|date|after:registered_at',
        ]);

        $meta = $domain->meta ?? [];
        unset($meta['awaiting_manual_registration']);

        $domain->update([
            'status'        => 'active',
            'registered_at' => $data['registered_at'],
            'expires_at'    => $data['expires_at'],
            'meta'          => $meta,
        ]);

        DomainLog::create([
            'tenant_id' => $domain->tenant_id,
            'domain_id' => $domain->id,
            'action'    => 'manual_register_confirmed',
            'request'   => ['by_user' => auth()->id(), 'registered_at' => $data['registered_at'], 'expires_at' => $data['expires_at']],
            'status'    => 'success',
        ]);

        return response()->json([
            'data'    => $domain->fresh()->load('client:id,name'),
            'message' => "{$domain->name} marked as registered.",
        ]);
    }

    /**
     * Reveal the transfer auth-info code — audited. If none is stored (the
     * common case for .tz domains — the registry doesn't hand it back on a
     * plain info query), staff can generate a fresh one: EPP UPDATE lets the
     * sponsoring registrar SET a new auth-info directly, unlike the portal's
     * client-facing flow which only asks the registry to email an existing
     * one to the registrant contact.
     */
    public function authInfo(Domain $domain)
    {
        if (!empty($domain->epp_auth_info)) {
            DomainLog::create([
                'tenant_id' => $domain->tenant_id,
                'domain_id' => $domain->id,
                'action'    => 'auth_info_revealed',
                'request'   => ['by_user' => auth()->id()],
                'status'    => 'success',
            ]);
            $this->notifyAuthInfoRevealed($domain);

            return response()->json(['auth_info' => $domain->epp_auth_info]);
        }

        if ($domain->meta['unmanaged'] ?? false) {
            return response()->json(['message' => 'This domain is managed externally — no code available here.'], 422);
        }

        $code = strtoupper(Str::random(4)) . '-' . strtoupper(Str::random(4)) . '-' . strtoupper(Str::random(4));

        try {
            $this->registrar->driverFor($domain->tenant_id, $domain->id)
                ->updateDomain($domain->name, ['auth_info' => $code]);
        } catch (RegistrarApiException $e) {
            return response()->json(['message' => 'Could not set a transfer code at the registry: '.$e->getMessage()], 422);
        }

        $domain->update(['epp_auth_info' => $code]);

        DomainLog::create([
            'tenant_id' => $domain->tenant_id,
            'domain_id' => $domain->id,
            'action'    => 'auth_info_generated',
            'request'   => ['by_user' => auth()->id()],
            'status'    => 'success',
        ]);
        $this->notifyAuthInfoRevealed($domain);

        return response()->json(['auth_info' => $code, 'generated' => true]);
    }

    private function tldOf(string $name): string
    {
        return strtolower(explode('.', $name, 2)[1] ?? '');
    }

    // ── WHM DNS for domains with no hosting account of their own ────────────
    //
    // For a domain that DOES have a hosting_accounts row on one of our WHM
    // servers, HostingAccountController::dnsZone()/addDnsRecord() already
    // cover it (its zone was created automatically when the account was
    // provisioned). This section is only for a domain with no such account
    // — mainly FRED-registered .tz domains — where staff explicitly asks us
    // to create a standalone DNS-only zone on one of our servers and manage
    // it here. Add-only, same as everywhere else WHM DNS is touched in this
    // codebase: see WhmService::addDnsRecord()'s doc comment for why
    // edit/delete are deliberately never exposed.
    //
    // Deliberately domain-centric, not a loop over every server: rather than
    // silently probing parse_dns_zone against each of the tenant's servers
    // (which could find a same-named zone that happens to exist on a server
    // for an unrelated reason, or hide a slow/erroring server behind a
    // false "no zone" result), staff explicitly picks the server once, and
    // that choice is remembered on the domain itself (meta.whm_dns) — a
    // nullable dns_server_id column would work as well, but Domain already
    // keeps this kind of "which external thing manages this" fact in meta
    // (whmcs_registrar, sponsoring_registrar, namecom, unmanaged, …), so
    // meta keeps this consistent with that existing convention rather than
    // adding a schema column for one more fact of the same shape.

    /** Tenant's active WHM servers for the "create DNS zone" picker — no credentials in the response. */
    public function dnsServers()
    {
        $tenantId = auth()->user()->tenant_id;

        $servers = Server::where('tenant_id', $tenantId)->where('is_active', true)
            ->orderBy('name')->get(['id', 'name', 'hostname']);

        return response()->json(['data' => $servers]);
    }

    /**
     * Whether a WHM DNS zone already exists for this domain — true only if
     * staff created one through createDnsZone() below (meta.whm_dns.server_id
     * recorded then). We never guess by probing servers; see this section's
     * header comment for why.
     */
    public function dnsZoneStatus(Domain $domain)
    {
        $tenantId = auth()->user()->tenant_id;
        $serverId = data_get($domain->meta, 'whm_dns.server_id');

        if (!$serverId) {
            return response()->json(['data' => ['exists' => false]]);
        }

        $server = Server::where('tenant_id', $tenantId)->find($serverId);
        if (!$server) {
            // The server was removed/reassigned since — treat as "not set up" rather than error.
            return response()->json(['data' => ['exists' => false]]);
        }

        return response()->json(['data' => [
            'exists'      => true,
            'server_id'   => $server->id,
            'server_name' => $server->name,
            'ip'          => data_get($domain->meta, 'whm_dns.ip'),
        ]]);
    }

    /**
     * Creates a new DNS-only zone on a server staff picks explicitly
     * (WhmService::createDnsZone() — WHM's `adddns`). Records which server
     * now hosts this domain's DNS in meta.whm_dns so every later read/add
     * call knows where to go without staff re-picking it. Optionally also
     * adds a "www" A record pointing at the same IP (root is already
     * covered — WHM's own zone template auto-generates the bare domain's A
     * record as part of adddns itself, so adding another here would just
     * create a duplicate).
     */
    public function createDnsZone(Request $request, Domain $domain)
    {
        $tenantId = auth()->user()->tenant_id;

        if (data_get($domain->meta, 'whm_dns.server_id')) {
            return response()->json(['message' => 'A DNS zone is already set up for this domain here.'], 422);
        }

        $data = $request->validate([
            'server_id'       => ['required', 'uuid', Rule::exists('servers', 'id')->where('tenant_id', $tenantId)],
            'ip'              => ['required', 'ip'],
            'point_to_server' => ['nullable', 'boolean'],
        ]);

        $server = Server::where('tenant_id', $tenantId)->findOrFail($data['server_id']);
        $whm = new WhmService($server);

        try {
            $whm->createDnsZone($domain->name, $data['ip']);
        } catch (WhmApiException $e) {
            return response()->json(['message' => 'Server rejected the request: ' . $e->getMessage()], 422);
        }

        $domain->update(['meta' => array_merge($domain->meta ?? [], [
            'whm_dns' => [
                'server_id'  => $server->id,
                'ip'         => $data['ip'],
                'created_at' => now()->toIso8601String(),
                'created_by' => auth()->id(),
            ],
        ])]);

        $wwwAdded = false;
        if (!array_key_exists('point_to_server', $data) || $data['point_to_server']) {
            try {
                $whm->addDnsRecord($domain->name, 'A', "www.{$domain->name}.", 14400, ['address' => $data['ip']]);
                $wwwAdded = true;
            } catch (WhmApiException) {
                // Non-fatal — the zone itself was created successfully; staff can add it by hand from the records table.
            }
        }

        return response()->json([
            'message' => 'DNS zone created on ' . $server->name . '.',
            'data'    => ['server_id' => $server->id, 'server_name' => $server->name, 'www_record_added' => $wwwAdded],
        ]);
    }

    /** Reads this domain's DNS zone from whichever server createDnsZone() recorded it on. */
    public function dnsZone(Domain $domain)
    {
        $tenantId = auth()->user()->tenant_id;
        $serverId = data_get($domain->meta, 'whm_dns.server_id');
        abort_unless($serverId, 404, 'No DNS zone has been created for this domain yet.');

        $server = Server::where('tenant_id', $tenantId)->find($serverId);
        abort_unless($server, 404, 'The server this domain\'s DNS zone was created on is no longer available.');

        try {
            $records = (new WhmService($server))->dnsZone($domain->name);
        } catch (WhmApiException) {
            return response()->json(['message' => 'Could not reach the server right now — please try again shortly.'], 422);
        }

        return response()->json(['data' => $records]);
    }

    /**
     * Adds one DNS zone record for this domain. Add-only, deliberately —
     * see WhmService::addDnsRecord()'s doc comment for why edit/delete
     * aren't exposed (WHM's line-number-based edit/remove calls proved
     * unreliable during live verification elsewhere in this codebase).
     */
    public function addDnsRecord(Request $request, Domain $domain)
    {
        $tenantId = auth()->user()->tenant_id;
        $serverId = data_get($domain->meta, 'whm_dns.server_id');
        abort_unless($serverId, 404, 'No DNS zone has been created for this domain yet.');

        $server = Server::where('tenant_id', $tenantId)->find($serverId);
        abort_unless($server, 404, 'The server this domain\'s DNS zone was created on is no longer available.');

        $data = $request->validate([
            'type'     => ['required', Rule::in(['A', 'AAAA', 'CNAME', 'TXT', 'MX'])],
            'name'     => 'required|string|max:255',
            'ttl'      => 'required|integer|min:60|max:2592000',
            'value'    => 'required_unless:type,MX|nullable|string|max:1024',
            'priority' => 'required_if:type,MX|nullable|integer|min:0|max:65535',
        ]);

        $name = str_ends_with($data['name'], '.') ? $data['name'] : "{$data['name']}.";

        $fields = match ($data['type']) {
            'A', 'AAAA' => ['address' => $data['value']],
            'CNAME' => ['cname' => str_ends_with($data['value'], '.') ? $data['value'] : "{$data['value']}."],
            'TXT' => ['txtdata' => $data['value']],
            'MX' => ['preference' => $data['priority'], 'exchange' => str_ends_with($data['value'], '.') ? $data['value'] : "{$data['value']}."],
        };

        try {
            (new WhmService($server))->addDnsRecord($domain->name, $data['type'], $name, $data['ttl'], $fields);
        } catch (WhmApiException $e) {
            return response()->json(['message' => 'Server rejected the record: ' . $e->getMessage()], 422);
        }

        return response()->json(['message' => 'DNS record added.']);
    }
}

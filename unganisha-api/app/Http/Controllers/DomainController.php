<?php

namespace App\Http\Controllers;

use App\Exceptions\RegistrarApiException;
use App\Models\Client;
use App\Models\Document;
use App\Models\Domain;
use App\Models\DomainLog;
use App\Models\DomainTld;
use App\Services\DocumentNumberService;
use App\Services\Registrar\DomainRegistrarManager;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
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

        try {
            $result = $this->registrar->driverFor(auth()->user()->tenant_id)->check($name);
        } catch (RegistrarApiException $e) {
            return response()->json(['message' => 'Registry check failed: ' . $e->getMessage()], 422);
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

        return response()->json(['data' => $query->paginate($request->get('per_page', 20))]);
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

        return response()->json(['data' => [
            'ok'          => $data['ok'] ?? false,
            'zones'       => $data['zones'] ?? [],
            'total'       => (float) $funded->sum('credit'),
            'funded_count'=> $funded->count(),
            // funded zones running low (below threshold) need a top-up
            'low'         => $funded->filter(fn ($z) => $z['credit'] < $threshold)->pluck('zone')->all(),
            'checked_at'  => $data['checked_at'] ?? null,
            'error'       => $data['error'] ?? null,
        ]]);
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

    public function logs(Domain $domain)
    {
        return response()->json(['data' => $domain->logs()->limit(50)->get()]);
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
            'name'      => ['required', 'string', 'max:255', 'regex:/^[a-z0-9][a-z0-9.-]+\.[a-z.]{2,}$/i', Rule::unique('domains', 'name')],
            'client_id' => ['required', 'uuid', Rule::exists('clients', 'id')->where('tenant_id', $tenantId)],
            'years'     => 'required|integer|min:1|max:10',
            'action'    => 'required|in:register,transfer',
            'auth_info' => 'required_if:action,transfer|nullable|string|max:255',
        ]);

        $name    = strtolower($data['name']);
        $pricing = DomainTld::priceFor($tenantId, $this->tldOf($name));
        if (!$pricing) {
            return response()->json(['message' => 'No pricing configured for .' . $this->tldOf($name) . ' — add it in Settings → Domains.'], 422);
        }
        if ($data['years'] < $pricing->years_min || $data['years'] > $pricing->years_max) {
            return response()->json(['message' => "Years must be between {$pricing->years_min} and {$pricing->years_max}."], 422);
        }

        // Registration orders must be for available names (read-only EPP check).
        if ($data['action'] === 'register') {
            try {
                $check = $this->registrar->driverFor($tenantId)->check($name);
                if (!$check['available']) {
                    return response()->json(['message' => "{$name} is not available: " . ($check['reason'] ?? 'taken')], 422);
                }
            } catch (RegistrarApiException $e) {
                return response()->json(['message' => 'Registry check failed: ' . $e->getMessage()], 422);
            }
        }

        $unitPrice = $data['action'] === 'register' ? $pricing->register_price : $pricing->transfer_price;
        $total     = round($unitPrice * $data['years'], 2);

        $result = DB::transaction(function () use ($data, $name, $tenantId, $total, $unitPrice) {
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

            $domain = Domain::create([
                'tenant_id'            => $tenantId,
                'client_id'            => $data['client_id'],
                'registrar_account_id' => $this->registrar->accountFor($tenantId)->id,
                'name'                 => $name,
                'status'               => 'pending',
                // off by default — the client opts in via the portal
                'auto_renew'           => false,
                'epp_auth_info'        => $data['auth_info'] ?? null,
                'meta'                 => [
                    'pending_action'    => $data['action'],
                    'pending_years'     => $data['years'],
                    'order_document_id' => $document->id,
                ],
            ]);

            return [$domain, $document];
        });

        [$domain, $document] = $result;

        return response()->json([
            'data'     => $domain->load('client:id,name'),
            'document' => ['id' => $document->id, 'document_number' => $document->document_number, 'total' => $document->total],
            'message'  => "Order created — invoice {$document->document_number}. The domain will be {$data['action']}ed at the registry once the invoice is paid.",
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

        return response()->json([
            'document' => ['id' => $document->id, 'document_number' => $document->document_number, 'total' => $document->total],
            'message'  => "Renewal invoice {$document->document_number} created — the registry renewal runs once it is paid.",
        ], 201);
    }

    /** Reveal the transfer auth-info code — audited. */
    public function authInfo(Domain $domain)
    {
        DomainLog::create([
            'tenant_id' => $domain->tenant_id,
            'domain_id' => $domain->id,
            'action'    => 'auth_info_revealed',
            'request'   => ['by_user' => auth()->id()],
            'status'    => 'success',
        ]);

        return response()->json(['auth_info' => $domain->epp_auth_info]);
    }

    private function tldOf(string $name): string
    {
        return strtolower(explode('.', $name, 2)[1] ?? '');
    }
}

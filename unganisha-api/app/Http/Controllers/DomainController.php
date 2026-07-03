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

        return response()->json(['data' => $query->paginate($request->get('per_page', 20))]);
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
                'auto_renew'           => true,
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

    /** Manual renewal order: creates the renewal invoice (EPP renew fires on payment — B3). */
    public function renew(Request $request, Domain $domain)
    {
        $data = $request->validate(['years' => 'required|integer|min:1|max:10']);

        $pricing = DomainTld::priceFor($domain->tenant_id, $this->tldOf($domain->name));
        if (!$pricing) {
            return response()->json(['message' => 'No pricing configured for this TLD.'], 422);
        }

        $total = round($pricing->renew_price * $data['years'], 2);

        $document = DB::transaction(function () use ($domain, $data, $total, $pricing) {
            $document = Document::create([
                'tenant_id'       => $domain->tenant_id,
                'client_id'       => $domain->client_id,
                'type'            => 'invoice',
                'document_number' => app(DocumentNumberService::class)->generate('invoice', $domain->tenant_id),
                'date'            => now()->toDateString(),
                'due_date'        => now()->addDays(7)->toDateString(),
                'subtotal'        => $total,
                'discount_amount' => 0,
                'tax_amount'      => 0,
                'total'           => $total,
                'status'          => 'sent',
                'notes'           => "Domain renewal: {$domain->name} ({$data['years']} year(s))",
                'created_by'      => auth()->id(),
            ]);

            $document->items()->create([
                'item_type'   => 'service',
                'description' => "Renew domain {$domain->name} — {$data['years']} year(s)",
                'quantity'    => $data['years'],
                'price'       => $pricing->renew_price,
                'tax_percent' => 0,
                'tax_amount'  => 0,
                'total'       => $total,
            ]);

            $domain->update(['meta' => array_merge($domain->meta ?? [], [
                'pending_action'      => 'renew',
                'pending_years'       => $data['years'],
                'renewal_document_id' => $document->id,
            ])]);

            return $document;
        });

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

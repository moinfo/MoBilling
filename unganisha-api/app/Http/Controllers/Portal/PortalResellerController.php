<?php

namespace App\Http\Controllers\Portal;

use App\Exceptions\RegistrarApiException;
use App\Http\Controllers\Controller;
use App\Models\Client;
use App\Models\Document;
use App\Models\Domain;
use App\Models\DomainTld;
use App\Services\CreditService;
use App\Services\DocumentNumberService;
use App\Services\Registrar\DomainRegistrarManager;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

/**
 * Domain reseller ordering — register/transfer/renew at MoBilling's own
 * wholesale cost (domain_tlds.reseller_price), paid instantly from the
 * client's wallet only (never invoiced-and-pay-later). Reuses the same
 * Document + Domain "pending_action" meta convention as the regular portal
 * domain order flow, so DocumentObserver fires the exact same EPP jobs
 * (RegisterDomainJob/TransferDomainJob/RenewDomainJob) once the invoice
 * flips to paid — no new registry-facing code needed.
 */
class PortalResellerController extends Controller
{
    private function client(Request $request): Client
    {
        return Client::withoutGlobalScopes()->findOrFail($request->user()->client_id);
    }

    /** Reseller status, wallet balance, and wholesale TLD pricing. */
    public function status(Request $request)
    {
        $client = $this->client($request);
        $tenantId = $request->user()->tenant_id;

        $tlds = DomainTld::where(fn ($q) => $q->where('tenant_id', $tenantId)->orWhereNull('tenant_id'))
            ->whereNotNull('reseller_price')
            ->where('is_active', true)
            ->orderBy('tld')->orderByRaw('tenant_id IS NULL')
            ->get()
            ->unique('tld')
            ->values()
            ->map(fn ($t) => [
                'tld'            => $t->tld,
                'reseller_price' => (float) $t->reseller_price,
                'years_min'      => $t->years_min,
                'years_max'      => $t->years_max,
            ]);

        $membership = $client->resellerSubscription();

        return response()->json(['data' => [
            'is_reseller'     => $membership !== null,
            'expire_date'     => $membership?->expire_date?->toDateString(),
            'wallet_balance'  => (float) $client->credit_balance,
            'tlds'            => $tlds,
        ]]);
    }

    /** Availability check at wholesale pricing. */
    public function check(Request $request, DomainRegistrarManager $registrar)
    {
        $client = $this->client($request);
        abort_unless($client->isReseller(), 403, 'Reseller membership required.');

        $data = $request->validate(['name' => 'required|string|max:255|regex:/^[a-z0-9][a-z0-9.-]+\.[a-z.]{2,}$/i']);
        $name = strtolower($data['name']);
        $tenantId = $request->user()->tenant_id;
        $tld = strtolower(explode('.', $name, 2)[1] ?? '');

        $pricing = DomainTld::priceFor($tenantId, $tld);
        if (!$pricing || $pricing->reseller_price === null) {
            return response()->json(['name' => $name, 'available' => false, 'pricing' => null,
                'message' => "We don't offer .{$tld} at reseller pricing — please contact us."]);
        }

        try {
            $result = $registrar->driverFor($tenantId)->check($name);
        } catch (RegistrarApiException) {
            return response()->json(['message' => 'Could not check availability right now — please try again.'], 422);
        }

        return response()->json([
            'name'      => $name,
            'available' => $result['available'],
            'pricing'   => [
                'reseller_price' => (float) $pricing->reseller_price,
                'years_min'      => $pricing->years_min,
                'years_max'      => $pricing->years_max,
            ],
        ]);
    }

    /** Register or transfer-in at wholesale price, paid immediately from the wallet. */
    public function order(Request $request, DomainRegistrarManager $registrar, CreditService $credit)
    {
        $user = $request->user();
        $tenantId = $user->tenant_id;
        $client = $this->client($request);
        abort_unless($client->isReseller(), 403, 'Reseller membership required.');

        $data = $request->validate([
            'name'      => ['required', 'string', 'max:255', 'regex:/^[a-z0-9][a-z0-9.-]+\.[a-z.]{2,}$/i', Rule::unique('domains', 'name')],
            'years'     => 'required|integer|min:1|max:10',
            'action'    => 'required|in:register,transfer',
            'auth_info' => 'required_if:action,transfer|nullable|string|max:255',
        ]);

        $name = strtolower($data['name']);
        $tld = strtolower(explode('.', $name, 2)[1] ?? '');
        $pricing = DomainTld::priceFor($tenantId, $tld);
        if (!$pricing || $pricing->reseller_price === null) {
            return response()->json(['message' => "We don't offer .{$tld} at reseller pricing — please contact us."], 422);
        }

        if ($data['action'] === 'register') {
            try {
                $check = $registrar->driverFor($tenantId)->check($name);
                if (!$check['available']) {
                    return response()->json(['message' => "{$name} is not available."], 422);
                }
            } catch (RegistrarApiException) {
                return response()->json(['message' => 'Could not verify availability — please try again.'], 422);
            }
        }

        $unitPrice = (float) $pricing->reseller_price;
        $total = round($unitPrice * $data['years'], 2);

        if ((float) $client->credit_balance < $total) {
            return response()->json([
                'message' => "Insufficient wallet balance. This order costs TZS " . number_format($total, 2)
                    . ' but your wallet holds TZS ' . number_format((float) $client->credit_balance, 2) . '. Please top up first.',
            ], 422);
        }

        try {
            $document = DB::transaction(function () use ($data, $name, $tenantId, $client, $total, $unitPrice, $registrar, $credit) {
            $document = Document::withoutGlobalScopes()->create([
                'tenant_id'       => $tenantId,
                'client_id'       => $client->id,
                'type'            => 'invoice',
                'document_number' => app(DocumentNumberService::class)->generate('invoice', $tenantId),
                'date'            => now()->toDateString(),
                'due_date'        => now()->toDateString(),
                'subtotal'        => $total,
                'discount_amount' => 0,
                'tax_amount'      => 0,
                'total'           => $total,
                'status'          => 'sent',
                'notes'           => "Reseller domain {$data['action']} (wholesale): {$name} ({$data['years']} year(s))",
            ]);

            $document->items()->create([
                'item_type'   => 'service',
                'description' => 'Reseller ' . $data['action'] . " domain {$name} — {$data['years']} year(s)",
                'quantity'    => $data['years'],
                'price'       => $unitPrice,
                'tax_percent' => 0,
                'tax_amount'  => 0,
                'total'       => $total,
            ]);

            Domain::create([
                'tenant_id'            => $tenantId,
                'client_id'            => $client->id,
                'registrar_account_id' => $registrar->accountFor($tenantId)->id,
                'name'                 => $name,
                'status'               => 'pending',
                'auto_renew'           => false,
                'epp_auth_info'        => $data['auth_info'] ?? null,
                'meta'                 => [
                    'pending_action'    => $data['action'],
                    'pending_years'     => $data['years'],
                    'order_document_id' => $document->id,
                    'portal_order'      => true,
                    'reseller_order'    => true,
                ],
            ]);

            // Row-locked wallet debit — if a concurrent spend drained the
            // balance between our pre-check above and here, this leaves the
            // invoice only partially paid; bail out and roll everything back
            // rather than leave a half-paid domain order sitting around.
            $credit->applyToInvoice($client, $document, null, null);
            if ($document->fresh()->status !== 'paid') {
                throw new \RuntimeException('Wallet balance changed — please try again.');
            }

            return $document;
            });
        } catch (\RuntimeException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return response()->json([
            'data'    => ['document_id' => $document->id, 'document_number' => $document->document_number, 'total' => (float) $document->total],
            'message' => "{$name} order paid from your wallet — the {$data['action']} is being processed.",
        ], 201);
    }

    /** Renew one of the reseller's own domains at wholesale price, paid immediately from the wallet. */
    public function renew(Request $request, Domain $domain, CreditService $credit)
    {
        $user = $request->user();
        $tenantId = $user->tenant_id;
        $client = $this->client($request);
        abort_unless($client->isReseller(), 403, 'Reseller membership required.');
        abort_unless($domain->client_id === $client->id, 404);

        if ($domain->meta['unmanaged'] ?? false) {
            return response()->json(['message' => 'This domain is renewed manually — please contact us.'], 422);
        }

        $data = $request->validate(['years' => 'required|integer|min:1|max:10']);

        $tld = strtolower(explode('.', $domain->name, 2)[1] ?? '');
        $pricing = DomainTld::priceFor($tenantId, $tld);
        if (!$pricing || $pricing->reseller_price === null) {
            return response()->json(['message' => "We don't offer .{$tld} at reseller pricing — please contact us."], 422);
        }

        $unitPrice = (float) $pricing->reseller_price;
        $total = round($unitPrice * $data['years'], 2);

        if ((float) $client->credit_balance < $total) {
            return response()->json([
                'message' => "Insufficient wallet balance. This renewal costs TZS " . number_format($total, 2)
                    . ' but your wallet holds TZS ' . number_format((float) $client->credit_balance, 2) . '. Please top up first.',
            ], 422);
        }

        try {
            $document = DB::transaction(function () use ($domain, $data, $tenantId, $client, $total, $unitPrice, $credit) {
                $document = Document::withoutGlobalScopes()->create([
                    'tenant_id'       => $tenantId,
                    'client_id'       => $client->id,
                    'type'            => 'invoice',
                    'document_number' => app(DocumentNumberService::class)->generate('invoice', $tenantId),
                    'date'            => now()->toDateString(),
                    'due_date'        => now()->toDateString(),
                    'subtotal'        => $total,
                    'discount_amount' => 0,
                    'tax_amount'      => 0,
                    'total'           => $total,
                    'status'          => 'sent',
                    'notes'           => "Reseller domain renewal (wholesale): {$domain->name} ({$data['years']} year(s))",
                ]);

                $document->items()->create([
                    'item_type'   => 'service',
                    'description' => "Reseller renew domain {$domain->name} — {$data['years']} year(s)",
                    'quantity'    => $data['years'],
                    'price'       => $unitPrice,
                    'tax_percent' => 0,
                    'tax_amount'  => 0,
                    'total'       => $total,
                ]);

                $domain->update(['meta' => array_merge($domain->meta ?? [], [
                    'pending_action'      => 'renew',
                    'pending_years'       => $data['years'],
                    'renewal_document_id' => $document->id,
                ])]);

                $credit->applyToInvoice($client, $document, null, null);
                if ($document->fresh()->status !== 'paid') {
                    throw new \RuntimeException('Wallet balance changed — please try again.');
                }

                return $document;
            });
        } catch (\RuntimeException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return response()->json([
            'data'    => ['document_id' => $document->id, 'document_number' => $document->document_number, 'total' => (float) $document->total],
            'message' => "{$domain->name} renewal paid from your wallet — processing now.",
        ], 201);
    }
}

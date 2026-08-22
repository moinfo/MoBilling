<?php

namespace App\Http\Controllers\Portal;

use App\Exceptions\RegistrarApiException;
use App\Http\Controllers\Controller;
use App\Models\Client;
use App\Models\ClientSubscription;
use App\Models\Document;
use App\Models\Domain;
use App\Models\DomainTld;
use App\Models\ProductService;
use App\Models\RecurringInvoiceLog;
use App\Services\CreditService;
use App\Services\DocumentNumberService;
use App\Services\Registrar\DomainRegistrarManager;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
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
        $product = ProductService::withoutGlobalScopes()
            ->where('tenant_id', $tenantId)->where('name', 'Reseller Membership')->first();

        return response()->json(['data' => [
            'is_reseller'      => $membership !== null,
            'expire_date'      => $membership?->expire_date?->toDateString(),
            'wallet_balance'   => (float) $client->credit_balance,
            'membership_price' => $product ? (float) $product->price : null,
            'tlds'             => $tlds,
        ]]);
    }

    /**
     * Self-service: create the annual membership invoice and let the client
     * pay it any way they like — Pesapal (card/mobile money), bank transfer
     * via the public /pay/{id} page, or applying wallet credit from the
     * portal invoice view. Becoming a reseller only needs the invoice paid;
     * SubscriptionActivationService::activateFor() (already wired into every
     * payment path) flips the membership to active the moment it is.
     */
    public function subscribe(Request $request)
    {
        $tenantId = $request->user()->tenant_id;
        $client = $this->client($request);

        if ($client->isReseller()) {
            return response()->json(['message' => 'You are already a reseller.'], 422);
        }

        $product = ProductService::withoutGlobalScopes()
            ->where('tenant_id', $tenantId)->where('name', 'Reseller Membership')->first();
        if (!$product) {
            return response()->json(['message' => 'Reseller membership is not available right now — please contact us.'], 422);
        }

        // Serialize per-client: double-clicks / slow network retries would
        // otherwise race past the "reuse pending invoice" check below and
        // each create their own membership subscription + invoice.
        $lock = Cache::lock("reseller-subscribe:{$client->id}", 10);

        try {
            return $lock->block(5, function () use ($client, $product, $tenantId) {
                // Re-use an already-pending, unpaid membership invoice rather
                // than spawning a duplicate every time the client (re)clicks.
                $pendingSubscription = ClientSubscription::withoutGlobalScopes()
                    ->where('tenant_id', $tenantId)->where('client_id', $client->id)
                    ->where('product_service_id', $product->id)->where('status', 'pending')
                    ->latest('created_at')->first();

                if ($pendingSubscription) {
                    $pendingLog = RecurringInvoiceLog::withoutGlobalScopes()
                        ->where('client_subscription_id', $pendingSubscription->id)
                        ->latest('invoice_created_at')->first();
                    $document = $pendingLog
                        ? Document::withoutGlobalScopes()->whereIn('status', ['sent', 'partial', 'overdue'])->find($pendingLog->document_id)
                        : null;
                    if ($document) {
                        return response()->json([
                            'data'    => ['document_id' => $document->id, 'document_number' => $document->document_number, 'total' => (float) $document->total],
                            'message' => "Invoice {$document->document_number} is awaiting payment — pay it to activate your reseller membership.",
                        ]);
                    }
                }

                $document = DB::transaction(function () use ($client, $product, $tenantId) {
                    $start = now()->startOfDay();

                    // No expire_date here — SubscriptionActivationService::activateFor()
                    // sets it to start_date + 1 cycle on payment (see ClientController::makeReseller).
                    $subscription = ClientSubscription::create([
                        'tenant_id'          => $tenantId,
                        'client_id'          => $client->id,
                        'product_service_id' => $product->id,
                        'label'              => 'Reseller Membership',
                        'quantity'           => 1,
                        'start_date'         => $start,
                        'status'             => 'pending',
                        'recurring_amount'   => $product->price,
                    ]);

                    $document = Document::withoutGlobalScopes()->create([
                        'tenant_id'       => $tenantId,
                        'client_id'       => $client->id,
                        'type'            => 'invoice',
                        'document_number' => app(DocumentNumberService::class)->generate('invoice', $tenantId),
                        'date'            => now()->toDateString(),
                        'due_date'        => now()->addDays(7)->toDateString(),
                        'subtotal'        => $product->price,
                        'discount_amount' => 0,
                        'tax_amount'      => 0,
                        'total'           => $product->price,
                        'status'          => 'sent',
                        'notes'           => 'Reseller Membership — annual fee (self-service, portal)',
                    ]);

                    $document->items()->create([
                        'product_service_id' => $product->id,
                        'item_type'          => 'service',
                        'description'        => 'Reseller Membership — annual fee',
                        'quantity'           => 1,
                        'price'              => $product->price,
                        'tax_percent'        => 0,
                        'tax_amount'         => 0,
                        'total'              => $product->price,
                    ]);

                    RecurringInvoiceLog::withoutGlobalScopes()->create([
                        'tenant_id'              => $tenantId,
                        'client_id'              => $client->id,
                        'product_service_id'     => $product->id,
                        'next_bill_date'         => $start->toDateString(),
                        'client_subscription_id' => $subscription->id,
                        'document_id'            => $document->id,
                        'invoice_created_at'     => now(),
                        'reminders_sent'         => [],
                    ]);

                    return $document;
                });

                return response()->json([
                    'data'    => ['document_id' => $document->id, 'document_number' => $document->document_number, 'total' => (float) $document->total],
                    'message' => "Invoice {$document->document_number} created — pay it any way you like to activate your reseller membership.",
                ], 201);
            });
        } catch (\Illuminate\Contracts\Cache\LockTimeoutException) {
            return response()->json(['message' => 'Still processing your previous request — please wait a moment and try again.'], 429);
        }
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
            'name'      => ['required', 'string', 'max:255', 'regex:/^[a-z0-9][a-z0-9.-]+\.[a-z.]{2,}$/i', Rule::unique('domains', 'name')->where(fn ($q) => $q->whereNotIn('status', ['cancelled', 'transferred_out']))],
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

            Domain::reviveOrCreate([
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

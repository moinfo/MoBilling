<?php

namespace App\Http\Controllers;

use App\Http\Requests\StoreClientRequest;
use App\Http\Resources\ClientResource;
use App\Models\Client;
use App\Models\ClientSubscription;
use App\Models\CommunicationLog;
use App\Models\Document;
use App\Models\PaymentIn;
use App\Models\ProductService;
use App\Models\RecurringInvoiceLog;
use App\Models\Refund;
use App\Services\DocumentNumberService;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class ClientController extends Controller
{
    public function index(Request $request)
    {
        $query = Client::query()
            ->withCount(['subscriptions as active_subscriptions_count' => function ($q) {
                $q->where('status', 'active');
            }])
            ->addSelect(['subscription_total' => ClientSubscription::selectRaw(
                    'COALESCE(SUM(client_subscriptions.quantity * product_services.price), 0)'
                )
                ->join('product_services', 'client_subscriptions.product_service_id', '=', 'product_services.id')
                ->whereColumn('client_subscriptions.client_id', 'clients.id')
                ->where('client_subscriptions.status', 'active')
                ->whereNull('client_subscriptions.deleted_at')
            ]);

        if ($request->has('search')) {
            $search = $request->search;
            $query->where(function ($q) use ($search) {
                $q->where('name', 'LIKE', "%{$search}%")
                  ->orWhere('email', 'LIKE', "%{$search}%")
                  ->orWhere('phone', 'LIKE', "%{$search}%");
            });
        }

        // Filter: only clients with (or without) active subscriptions
        if ($request->filled('has_subscriptions')) {
            $activeSubs = fn ($q) => $q->where('status', 'active');
            $request->boolean('has_subscriptions')
                ? $query->whereHas('subscriptions', $activeSubs)
                : $query->whereDoesntHave('subscriptions', $activeSubs);
        }

        $query->orderBy(...match ($request->get('sort')) {
            'subscriptions' => ['active_subscriptions_count', 'desc'],
            'amount'        => ['subscription_total', 'desc'],
            'newest'        => ['clients.created_at', 'desc'],
            default         => ['name', 'asc'],
        })->orderBy('name');

        return ClientResource::collection(
            $query->paginate($request->per_page ?? 20)
        );
    }

    /** Summary numbers for the Clients page dashboard strip. */
    public function stats(Request $request)
    {
        $stats = [
            'total_clients'        => Client::count(),
            'with_subscriptions'   => Client::whereHas('subscriptions', fn ($q) => $q->where('status', 'active'))->count(),
            'active_subscriptions' => ClientSubscription::where('status', 'active')->count(),
            'new_this_month'       => Client::where('created_at', '>=', now()->startOfMonth())->count(),
        ];
        $stats['without_subscriptions'] = $stats['total_clients'] - $stats['with_subscriptions'];

        if ($request->user()->hasPermission('client_profile.subscription_value')) {
            $stats['subscription_value'] = (float) ClientSubscription::where('client_subscriptions.status', 'active')
                ->join('product_services', 'client_subscriptions.product_service_id', '=', 'product_services.id')
                ->selectRaw('COALESCE(SUM(client_subscriptions.quantity * product_services.price), 0) as v')
                ->value('v');
            $stats['credit_balance_total'] = (float) Client::sum('credit_balance');
        }

        return response()->json(['data' => $stats]);
    }

    public function store(StoreClientRequest $request)
    {
        $client = Client::create($request->validated());
        return new ClientResource($client);
    }

    public function show(Client $client)
    {
        return new ClientResource($client);
    }

    public function update(StoreClientRequest $request, Client $client)
    {
        $client->update($request->validated());
        return new ClientResource($client);
    }

    public function destroy(Client $client)
    {
        $client->delete();
        return response()->json(['message' => 'Client deleted successfully']);
    }

    /**
     * WHMCS-style "Merge Clients": {client} is the "First Client" (the one
     * being viewed); the request names the "Second Client" and which of the
     * two survives. See ClientMergeService for exactly what moves.
     */
    public function merge(Request $request, Client $client, \App\Services\ClientMergeService $merger)
    {
        $data = $request->validate([
            'second_client_id' => 'required|uuid',
            'keep'              => 'required|in:first,second',
        ]);

        $second = Client::findOrFail($data['second_client_id']);

        if ($second->id === $client->id) {
            return response()->json(['message' => 'Choose two different clients to merge.'], 422);
        }

        [$survivor, $absorbed] = $data['keep'] === 'first' ? [$client, $second] : [$second, $client];

        $moved = $merger->merge($survivor, $absorbed);

        return response()->json([
            'data'    => ['survivor_id' => $survivor->id, 'moved' => $moved],
            'message' => "Merged {$absorbed->name} into {$survivor->name}.",
        ]);
    }

    /** Staff-only admin notes (never shown to the client). */
    public function updateNotes(\Illuminate\Http\Request $request, Client $client)
    {
        $data = $request->validate(['notes' => 'nullable|string|max:10000']);
        $client->update(['notes' => $data['notes'] ?? null]);

        return response()->json(['message' => 'Notes saved.']);
    }

    /**
     * Communications sent to a client — email/WhatsApp/SMS with delivery
     * status. Used by the hosting Service Management page so staff can see
     * whether a welcome/password message actually went out.
     */
    public function communications(Request $request, Client $client)
    {
        $query = CommunicationLog::where('client_id', $client->id)
            ->orderByDesc('created_at');

        if ($request->filled('types')) {
            $query->whereIn('type', explode(',', $request->string('types')));
        }

        return response()->json([
            'data' => $query->limit((int) $request->get('limit', 30))
                ->get(['id', 'channel', 'type', 'recipient', 'subject', 'message', 'status', 'error', 'created_at']),
        ]);
    }

    /**
     * Grant domain-reseller status: creates a subscription (+ its first
     * invoice) to the tenant's "Reseller Membership" product. Status is
     * derived live from that subscription being active — never a separate
     * flag — so non-payment silently and automatically revokes it via the
     * existing recurring-billing/auto-suspend engine.
     */
    public function makeReseller(Client $client)
    {
        if ($client->isReseller()) {
            return response()->json(['message' => "{$client->name} is already a reseller."], 422);
        }

        $tenantId = auth()->user()->tenant_id;
        $product = ProductService::withoutGlobalScopes()
            ->where('tenant_id', $tenantId)->where('name', 'Reseller Membership')->first();

        if (!$product) {
            return response()->json(['message' => 'Reseller Membership product not found — contact support.'], 422);
        }

        [$subscription, $document] = DB::transaction(function () use ($client, $product, $tenantId) {
            $start = now()->startOfDay();

            // No expire_date here: SubscriptionActivationService::activateFor()
            // sets it to start_date + 1 cycle when the invoice below gets paid
            // (it bases the new expiry on the existing expire_date, or
            // start_date if unset — pre-setting it here would double-count
            // the first year the moment payment activates the subscription).
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
                'notes'           => 'Reseller Membership — annual fee',
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

            // Links the invoice to the subscription so payment (any method)
            // activates it — same mechanism every other order flow uses.
            RecurringInvoiceLog::withoutGlobalScopes()->create([
                'tenant_id'               => $tenantId,
                'client_id'               => $client->id,
                'product_service_id'      => $product->id,
                'next_bill_date'          => $start->toDateString(),
                'client_subscription_id'  => $subscription->id,
                'document_id'             => $document->id,
                'invoice_created_at'      => now(),
                'reminders_sent'          => [],
            ]);

            return [$subscription, $document];
        });

        try {
            if ($client->email || $client->phone) {
                $client->notifyNow(new \App\Notifications\InvoiceSentNotification($document));
            }
        } catch (\Throwable $e) {
            report($e);
        }

        return response()->json([
            'data' => [
                'subscription_id' => $subscription->id,
                'document_id'     => $document->id,
                'document_number' => $document->document_number,
            ],
            'message' => "Reseller invoice {$document->document_number} created — {$client->name} becomes a reseller once it's paid.",
        ], 201);
    }

    public function profile(Client $client)
    {
        $cycleIntervals = [
            'monthly' => '1 month',
            'quarterly' => '3 months',
            'half_yearly' => '6 months',
            'yearly' => '1 year',
        ];

        $today = Carbon::today();

        // Subscriptions with next bill calculation
        $subscriptions = ClientSubscription::where('client_id', $client->id)
            ->with('productService')
            ->orderByDesc('created_at')
            ->get()
            ->map(function ($sub) use ($cycleIntervals, $today) {
                $product = $sub->productService;
                $interval = $cycleIntervals[$product->billing_cycle ?? ''] ?? null;
                $nextBill = null;

                if ($sub->status === 'active' && $interval) {
                    $date = $sub->start_date->copy();
                    while ($date->lt($today)) {
                        $date->add($interval);
                    }
                    // Skip forward past dates that already have a paid invoice
                    while (
                        RecurringInvoiceLog::where('client_id', $sub->client_id)
                            ->where('product_service_id', $sub->product_service_id)
                            ->where('next_bill_date', $date->format('Y-m-d'))
                            ->whereHas('document', fn ($q) => $q->where('status', 'paid'))
                            ->exists()
                    ) {
                        $date->add($interval);
                    }
                    $nextBill = $date->format('Y-m-d');
                }

                return [
                    'id' => $sub->id,
                    'product_service_name' => $product->name,
                    'label' => $sub->label,
                    'billing_cycle' => $product->billing_cycle,
                    'quantity' => $sub->quantity,
                    'price' => $product->price,
                    'start_date' => $sub->start_date->format('Y-m-d'),
                    'status' => $sub->status,
                    'next_bill' => $nextBill,
                ];
            });

        // Invoices (documents of type invoice)
        $invoices = Document::where('client_id', $client->id)
            ->where('type', 'invoice')
            ->with(['items', 'payments'])
            ->orderByDesc('date')
            ->limit(50)
            ->get()
            ->map(function ($doc) {
                // Late fee = sum of line items with 'Late payment fee' description
                $lateFee = $doc->items
                    ->filter(fn ($item) => str_contains($item->description ?? '', 'Late payment fee'))
                    ->sum('total');

                return [
                    'id' => $doc->id,
                    'document_number' => $doc->document_number,
                    'description' => $doc->items->first()?->description ?? $doc->notes,
                    'date' => $doc->date?->format('Y-m-d'),
                    'due_date' => $doc->due_date?->format('Y-m-d'),
                    'subtotal' => round((float) $doc->total - $lateFee, 2),
                    'late_fee' => round($lateFee, 2),
                    'total' => $doc->total,
                    'paid_amount' => round((float) $doc->paid_amount, 2),
                    'balance_due' => round((float) $doc->balance_due, 2),
                    'status' => $doc->status,
                ];
            });

        // Quotations (Document.type = 'quotation') — WHMCS "Current Quotes"
        $quotations = Document::where('client_id', $client->id)
            ->where('type', 'quotation')
            ->with('items')
            ->orderByDesc('date')
            ->limit(50)
            ->get()
            ->map(fn ($q) => [
                'id' => $q->id,
                'document_number' => $q->document_number,
                'subject' => $q->items->first()?->description ?? $q->notes,
                'date' => $q->date?->format('Y-m-d'),
                'valid_until' => $q->due_date?->format('Y-m-d'),
                'total' => $q->total,
                'status' => $q->status,
            ]);

        // Subscription addons — WHMCS "Addons" table
        $addons = \App\Models\SubscriptionAddon::whereHas('subscription', fn ($q) => $q->where('client_id', $client->id))
            ->with('subscription')
            ->orderByDesc('created_at')
            ->get()
            ->map(fn ($a) => [
                'id' => $a->id,
                'name' => $a->name,
                'price' => $a->price,
                'billing_cycle' => $a->billing_cycle,
                'start_date' => $a->subscription?->start_date?->format('Y-m-d'),
                'status' => $a->status,
            ]);

        // Payments
        $payments = PaymentIn::whereHas('document', fn ($q) => $q->where('client_id', $client->id))
            ->with('document')
            ->orderByDesc('payment_date')
            ->limit(50)
            ->get()
            ->map(fn ($p) => [
                'id' => $p->id,
                'amount' => $p->amount,
                'payment_date' => $p->payment_date?->format('Y-m-d'),
                'payment_method' => $p->payment_method,
                'reference' => $p->reference,
                'document_number' => $p->document?->document_number,
            ]);

        // Communication logs
        $communicationLogs = CommunicationLog::where('client_id', $client->id)
            ->orderByDesc('created_at')
            ->limit(50)
            ->get()
            ->map(fn ($log) => [
                'id' => $log->id,
                'channel' => $log->channel,
                'type' => $log->type,
                'recipient' => $log->recipient,
                'subject' => $log->subject,
                'message' => $log->message,
                'status' => $log->status,
                'error' => $log->error,
                'created_at' => $log->created_at?->toISOString(),
            ]);

        // WHMCS-style billing breakdown by status
        $breakdownRaw = Document::where('client_id', $client->id)
            ->where('type', 'invoice')
            ->selectRaw('status, COUNT(*) as n, SUM(total) as sum')
            ->groupBy('status')->get()->keyBy('status');
        $breakdown = collect(['paid', 'sent', 'partial', 'overdue', 'draft', 'cancelled'])
            ->mapWithKeys(fn ($st) => [$st => [
                'count' => (int) ($breakdownRaw[$st]->n ?? 0),
                'total' => (float) ($breakdownRaw[$st]->sum ?? 0),
            ]]);
        $refundAgg = \App\Models\Refund::where('client_id', $client->id)
            ->selectRaw('COUNT(*) as n, SUM(amount) as sum')->first();
        $breakdown['refunded'] = [
            'count' => (int) ($refundAgg->n ?? 0),
            'total' => (float) ($refundAgg->sum ?? 0),
        ];

        // Additional contacts (WHMCS-style secondary people at the client's company)
        $contacts = \App\Models\ClientContact::where('client_id', $client->id)
            ->orderBy('name')
            ->get(['id', 'name', 'email', 'phone', 'role', 'notes']);

        // Domains
        $domains = \App\Models\Domain::where('client_id', $client->id)
            ->orderBy('name')
            ->get()
            ->map(fn ($d) => [
                'id'            => $d->id,
                'name'          => $d->name,
                'registrar'     => ($d->meta['unmanaged'] ?? false) ? 'External (gTLD)' : 'FRED (.TZ Registry)',
                'registered_at' => $d->registered_at?->format('Y-m-d'),
                'expires_at'    => $d->expires_at?->format('Y-m-d'),
                'auto_renew'    => $d->auto_renew,
                'status'        => $d->status,
            ]);

        // Tickets
        $tickets = \App\Models\Ticket::where('client_id', $client->id)
            ->orderByDesc('last_reply_at')->limit(10)
            ->get()
            ->map(fn ($t) => [
                'id'            => $t->id,
                'ticket_number' => $t->ticket_number,
                'subject'       => $t->subject,
                'status'        => $t->status,
                'last_reply_at' => $t->last_reply_at?->toISOString(),
            ]);

        // Hosting accounts
        $hosting = \App\Models\HostingAccount::whereHas('subscription', fn ($q) => $q->where('client_id', $client->id))
            ->get()
            ->map(fn ($h) => [
                'id'              => $h->id,
                'domain'          => $h->domain,
                'cpanel_username' => $h->cpanel_username,
                'status'          => $h->status,
            ]);

        // Summary stats.
        //
        // Both figures describe one set of documents: this client's live
        // invoices. Previously invoiced counted drafts and cancelled invoices
        // while paid counted payments against any document of theirs —
        // quotes, proformas, credit notes — and ignored refunds, so the pair
        // could not be subtracted to give anything meaningful. Same shape as
        // the fix in Portal\PortalDashboardController::summary().
        $liveInvoices = fn ($q) => $q
            ->where('client_id', $client->id)
            ->where('type', 'invoice')
            ->whereNotIn('status', ['draft', 'cancelled']);

        $totalInvoiced = Document::where('client_id', $client->id)
            ->where('type', 'invoice')
            ->whereNotIn('status', ['draft', 'cancelled'])
            ->sum('total');
        $totalPaid = round(
            (float) PaymentIn::whereHas('document', $liveInvoices)->sum('amount')
            - (float) Refund::whereHas('document', $liveInvoices)->sum('amount'),
            2
        );
        $activeSubscriptions = $subscriptions->where('status', 'active')->count();

        // Total subscription value = sum of (price * quantity) for active subs
        $totalSubscriptionValue = $subscriptions
            ->where('status', 'active')
            ->sum(fn ($s) => (float) $s['price'] * (int) $s['quantity']);

        return response()->json([
            'data' => [
                'client' => [
                    'id' => $client->id,
                    'name' => $client->name,
                    'email' => $client->email,
                    'phone' => $client->phone,
                    'address' => $client->address,
                    'tax_id' => $client->tax_id,
                    'created_at' => $client->created_at,
                    'first_name' => $client->first_name,
                    'last_name' => $client->last_name,
                    'company_name' => $client->company_name,
                    'address_1' => $client->address_1,
                    'address_2' => $client->address_2,
                    'city' => $client->city,
                    'state' => $client->state,
                    'postcode' => $client->postcode,
                    'country' => $client->country,
                ],
                'billing_breakdown' => $breakdown,
            'contacts' => $contacts,
            'domains' => $domains,
            'tickets' => $tickets,
            'hosting_accounts' => $hosting,
            'credit_balance' => (float) $client->credit_balance,
            'is_reseller' => $client->isReseller(),
            'reseller_membership' => $client->resellerSubscription()
                ? ['expire_date' => $client->resellerSubscription()->expire_date?->toDateString()]
                : null,
            'client_since' => $client->created_at?->format('Y-m-d'),
            'client_status' => $client->status ?? 'active',
            'admin_notes' => $client->notes,
            'summary' => [
                    'total_invoiced' => round((float) $totalInvoiced, 2),
                    'total_paid' => round((float) $totalPaid, 2),
                    'balance' => round((float) $totalInvoiced - (float) $totalPaid, 2),
                    'active_subscriptions' => $activeSubscriptions,
                    'total_subscription_value' => round($totalSubscriptionValue, 2),
                ],
                'subscriptions' => $subscriptions->values(),
                'addons' => $addons->values(),
                'invoices' => $invoices->values(),
                'quotations' => $quotations->values(),
                'payments' => $payments->values(),
                'communication_logs' => $communicationLogs->values(),
            ],
        ]);
    }
}

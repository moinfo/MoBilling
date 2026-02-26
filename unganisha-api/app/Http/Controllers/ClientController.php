<?php

namespace App\Http\Controllers;

use App\Http\Requests\StoreClientRequest;
use App\Http\Resources\ClientResource;
use App\Models\Client;
use App\Models\ClientSubscription;
use App\Models\CommunicationLog;
use App\Models\Document;
use App\Models\PaymentIn;
use App\Models\RecurringInvoiceLog;
use Carbon\Carbon;
use Illuminate\Http\Request;

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

        return ClientResource::collection(
            $query->orderBy('name')->paginate($request->per_page ?? 20)
        );
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
            ->with('items')
            ->orderByDesc('date')
            ->limit(50)
            ->get()
            ->map(fn ($doc) => [
                'id' => $doc->id,
                'document_number' => $doc->document_number,
                'date' => $doc->date?->format('Y-m-d'),
                'due_date' => $doc->due_date?->format('Y-m-d'),
                'total' => $doc->total,
                'status' => $doc->status,
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

        // Summary stats
        $totalInvoiced = Document::where('client_id', $client->id)
            ->where('type', 'invoice')
            ->sum('total');
        $totalPaid = PaymentIn::whereHas('document', fn ($q) => $q->where('client_id', $client->id))
            ->sum('amount');
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
                ],
                'summary' => [
                    'total_invoiced' => round((float) $totalInvoiced, 2),
                    'total_paid' => round((float) $totalPaid, 2),
                    'balance' => round((float) $totalInvoiced - (float) $totalPaid, 2),
                    'active_subscriptions' => $activeSubscriptions,
                    'total_subscription_value' => round($totalSubscriptionValue, 2),
                ],
                'subscriptions' => $subscriptions->values(),
                'invoices' => $invoices->values(),
                'payments' => $payments->values(),
                'communication_logs' => $communicationLogs->values(),
            ],
        ]);
    }
}

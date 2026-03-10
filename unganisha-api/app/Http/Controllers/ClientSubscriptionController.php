<?php

namespace App\Http\Controllers;

use App\Http\Requests\StoreClientSubscriptionRequest;
use App\Http\Resources\ClientSubscriptionResource;
use App\Models\ClientSubscription;
use App\Models\Document;
use App\Models\RecurringInvoiceLog;
use App\Notifications\InvoiceSentNotification;
use App\Services\DocumentNumberService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class ClientSubscriptionController extends Controller
{
    public function index(Request $request)
    {
        $query = ClientSubscription::with('client', 'productService');

        if ($request->has('client_id')) {
            $query->where('client_id', $request->client_id);
        }

        if ($request->has('status')) {
            $query->where('status', $request->status);
        }

        if ($request->has('search')) {
            $search = $request->search;
            $query->where(function ($q) use ($search) {
                $q->where('label', 'LIKE', "%{$search}%")
                  ->orWhereHas('client', fn ($q) => $q->where('name', 'LIKE', "%{$search}%"))
                  ->orWhereHas('productService', fn ($q) => $q->where('name', 'LIKE', "%{$search}%"));
            });
        }

        // Sorting
        $sortable = ['status', 'start_date', 'created_at', 'label', 'quantity'];
        $sortBy = in_array($request->sort_by, $sortable) ? $request->sort_by : 'created_at';
        $sortDir = $request->sort_dir === 'asc' ? 'asc' : 'desc';

        return ClientSubscriptionResource::collection(
            $query->orderBy($sortBy, $sortDir)->paginate($request->per_page ?? 20)
        );
    }

    public function store(StoreClientSubscriptionRequest $request)
    {
        return DB::transaction(function () use ($request) {
            $validated = $request->validated();
            $status = $validated['status'] ?? 'pending';

            $subscription = ClientSubscription::create(array_merge(
                $validated,
                ['status' => $status]
            ));
            $subscription->load('client', 'productService');

            // Set initial expire_date from start_date + billing_cycle
            if ($subscription->start_date && $subscription->productService?->billing_cycle) {
                $expireDate = match ($subscription->productService->billing_cycle) {
                    'monthly' => $subscription->start_date->copy()->addMonth(),
                    'quarterly' => $subscription->start_date->copy()->addMonths(3),
                    'half_yearly' => $subscription->start_date->copy()->addMonths(6),
                    'yearly' => $subscription->start_date->copy()->addYear(),
                    default => null,
                };
                if ($expireDate) {
                    $subscription->update(['expire_date' => $expireDate]);
                }
            }

            // Only create an invoice when status is "pending"
            if ($status === 'pending') {
                $client = $subscription->client;
                $product = $subscription->productService;
                $tenant = auth()->user()->tenant;
                $qty = $subscription->quantity;

                // Calculate line item
                $lineBase = $qty * (float) $product->price;
                $lineTax = $lineBase * ((float) ($product->tax_percent ?? 0) / 100);
                $lineTotal = $lineBase + $lineTax;

                $description = $product->name;
                if ($subscription->label) {
                    $description .= " — {$subscription->label}";
                }

                $dueDate = $subscription->start_date;

                $document = Document::create([
                    'client_id' => $client->id,
                    'type' => 'invoice',
                    'document_number' => app(DocumentNumberService::class)
                        ->generate('invoice', $tenant->id),
                    'date' => now()->format('Y-m-d'),
                    'due_date' => $dueDate->format('Y-m-d'),
                    'subtotal' => round($lineBase, 2),
                    'discount_amount' => 0,
                    'tax_amount' => round($lineTax, 2),
                    'total' => round($lineTotal, 2),
                    'notes' => 'Invoice for new subscription',
                    'status' => 'sent',
                    'created_by' => auth()->id(),
                ]);

                $document->items()->create([
                    'product_service_id' => $product->id,
                    'item_type' => $product->type,
                    'description' => $description,
                    'quantity' => $qty,
                    'price' => $product->price,
                    'discount_type' => 'percent',
                    'discount_value' => 0,
                    'tax_percent' => $product->tax_percent ?? 0,
                    'tax_amount' => round($lineTax, 2),
                    'total' => round($lineTotal, 2),
                    'unit' => $product->unit,
                ]);

                // Log it so the recurring system knows this cycle is covered
                RecurringInvoiceLog::create([
                    'client_id' => $client->id,
                    'product_service_id' => $product->id,
                    'client_subscription_id' => $subscription->id,
                    'document_id' => $document->id,
                    'next_bill_date' => $dueDate,
                    'invoice_created_at' => now(),
                    'reminders_sent' => [],
                ]);

                // Send invoice to client (email + SMS if tenant allows)
                $document->load('items', 'client');
                $client->notify(new InvoiceSentNotification($document));
            }

            return new ClientSubscriptionResource($subscription);
        });
    }

    public function bulkStore(Request $request)
    {
        $request->validate([
            'client_id' => 'required|uuid|exists:clients,id',
            'start_date' => 'required|date',
            'status' => 'in:pending,active',
            'items' => 'required|array|min:1',
            'items.*.product_service_id' => 'required|uuid|exists:product_services,id',
            'items.*.label' => 'nullable|string|max:255',
            'items.*.quantity' => 'integer|min:1',
        ]);

        return DB::transaction(function () use ($request) {
            $status = $request->status ?? 'pending';
            $subscriptions = [];

            foreach ($request->items as $item) {
                $subscription = ClientSubscription::create([
                    'client_id' => $request->client_id,
                    'product_service_id' => $item['product_service_id'],
                    'label' => $item['label'] ?? null,
                    'quantity' => $item['quantity'] ?? 1,
                    'start_date' => $request->start_date,
                    'status' => $status,
                ]);
                $subscription->load('client', 'productService');

                // Set initial expire_date
                if ($subscription->start_date && $subscription->productService?->billing_cycle) {
                    $expireDate = match ($subscription->productService->billing_cycle) {
                        'monthly' => $subscription->start_date->copy()->addMonth(),
                        'quarterly' => $subscription->start_date->copy()->addMonths(3),
                        'half_yearly' => $subscription->start_date->copy()->addMonths(6),
                        'yearly' => $subscription->start_date->copy()->addYear(),
                        default => null,
                    };
                    if ($expireDate) {
                        $subscription->update(['expire_date' => $expireDate]);
                    }
                }

                $subscriptions[] = $subscription;
            }

            // Generate one combined invoice when status is "pending"
            if ($status === 'pending' && count($subscriptions) > 0) {
                $client = $subscriptions[0]->client;
                $tenant = auth()->user()->tenant;
                $dueDate = $subscriptions[0]->start_date;

                $subtotal = 0;
                $taxTotal = 0;
                $lineItems = [];

                foreach ($subscriptions as $sub) {
                    $product = $sub->productService;
                    $qty = $sub->quantity;
                    $lineBase = $qty * (float) $product->price;
                    $lineTax = $lineBase * ((float) ($product->tax_percent ?? 0) / 100);
                    $lineTotal = $lineBase + $lineTax;

                    $description = $product->name;
                    if ($sub->label) {
                        $description .= " — {$sub->label}";
                    }

                    $subtotal += $lineBase;
                    $taxTotal += $lineTax;

                    $lineItems[] = [
                        'product_service_id' => $product->id,
                        'item_type' => $product->type,
                        'description' => $description,
                        'quantity' => $qty,
                        'price' => $product->price,
                        'discount_type' => 'percent',
                        'discount_value' => 0,
                        'tax_percent' => $product->tax_percent ?? 0,
                        'tax_amount' => round($lineTax, 2),
                        'total' => round($lineTotal, 2),
                        'unit' => $product->unit,
                    ];
                }

                $document = Document::create([
                    'client_id' => $client->id,
                    'type' => 'invoice',
                    'document_number' => app(DocumentNumberService::class)
                        ->generate('invoice', $tenant->id),
                    'date' => now()->format('Y-m-d'),
                    'due_date' => $dueDate->format('Y-m-d'),
                    'subtotal' => round($subtotal, 2),
                    'discount_amount' => 0,
                    'tax_amount' => round($taxTotal, 2),
                    'total' => round($subtotal + $taxTotal, 2),
                    'notes' => 'Invoice for new subscriptions',
                    'status' => 'sent',
                    'created_by' => auth()->id(),
                ]);

                foreach ($lineItems as $lineItem) {
                    $document->items()->create($lineItem);
                }

                // Log each subscription for the recurring system
                foreach ($subscriptions as $sub) {
                    RecurringInvoiceLog::updateOrCreate(
                        [
                            'client_id' => $client->id,
                            'product_service_id' => $sub->product_service_id,
                            'client_subscription_id' => $sub->id,
                            'next_bill_date' => $dueDate,
                        ],
                        [
                            'document_id' => $document->id,
                            'invoice_created_at' => now(),
                            'reminders_sent' => [],
                        ]
                    );
                }

                // Send invoice to client
                $document->load('items', 'client');
                $client->notify(new InvoiceSentNotification($document));
            }

            return ClientSubscriptionResource::collection($subscriptions);
        });
    }

    public function show(ClientSubscription $clientSubscription)
    {
        return new ClientSubscriptionResource(
            $clientSubscription->load('client', 'productService')
        );
    }

    public function update(StoreClientSubscriptionRequest $request, ClientSubscription $clientSubscription)
    {
        $clientSubscription->update($request->validated());
        return new ClientSubscriptionResource(
            $clientSubscription->load('client', 'productService')
        );
    }

    public function generateInvoice(ClientSubscription $clientSubscription)
    {
        $clientSubscription->load('client', 'productService');
        $client = $clientSubscription->client;
        $product = $clientSubscription->productService;

        if (!$client || !$product) {
            return response()->json(['message' => 'Subscription is missing client or product data.'], 422);
        }

        return DB::transaction(function () use ($clientSubscription, $client, $product) {
            $tenant = auth()->user()->tenant;
            $qty = $clientSubscription->quantity;

            $lineBase = $qty * (float) $product->price;
            $lineTax = $lineBase * ((float) ($product->tax_percent ?? 0) / 100);
            $lineTotal = $lineBase + $lineTax;

            $description = $product->name;
            if ($clientSubscription->label) {
                $description .= " — {$clientSubscription->label}";
            }

            $document = Document::create([
                'client_id' => $client->id,
                'type' => 'invoice',
                'document_number' => app(DocumentNumberService::class)
                    ->generate('invoice', $tenant->id),
                'date' => now()->format('Y-m-d'),
                'due_date' => now()->addDays(14)->format('Y-m-d'),
                'subtotal' => round($lineBase, 2),
                'discount_amount' => 0,
                'tax_amount' => round($lineTax, 2),
                'total' => round($lineTotal, 2),
                'notes' => "Invoice from subscription: {$clientSubscription->label}",
                'status' => 'sent',
                'created_by' => auth()->id(),
            ]);

            $document->items()->create([
                'product_service_id' => $product->id,
                'item_type' => $product->type,
                'description' => $description,
                'quantity' => $qty,
                'price' => $product->price,
                'discount_type' => 'percent',
                'discount_value' => 0,
                'tax_percent' => $product->tax_percent ?? 0,
                'tax_amount' => round($lineTax, 2),
                'total' => round($lineTotal, 2),
                'unit' => $product->unit,
            ]);

            RecurringInvoiceLog::create([
                'client_id' => $client->id,
                'product_service_id' => $product->id,
                'client_subscription_id' => $clientSubscription->id,
                'document_id' => $document->id,
                'next_bill_date' => now(),
                'invoice_created_at' => now(),
                'reminders_sent' => [],
            ]);

            $document->load('items', 'client');
            $client->notify(new InvoiceSentNotification($document));

            return response()->json([
                'message' => "Invoice {$document->document_number} created and sent to {$client->name}.",
                'data' => [
                    'document_id' => $document->id,
                    'document_number' => $document->document_number,
                ],
            ]);
        });
    }

    public function updateExpireDate(Request $request, ClientSubscription $clientSubscription)
    {
        $request->validate([
            'expire_date' => 'required|date',
        ]);

        $clientSubscription->update(['expire_date' => $request->expire_date]);

        return new ClientSubscriptionResource(
            $clientSubscription->load('client', 'productService')
        );
    }

    public function destroy(ClientSubscription $clientSubscription)
    {
        $clientSubscription->delete();
        return response()->json(['message' => 'Subscription deleted successfully']);
    }
}

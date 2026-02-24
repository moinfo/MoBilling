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

        return ClientSubscriptionResource::collection(
            $query->orderByDesc('created_at')->paginate($request->per_page ?? 20)
        );
    }

    public function store(StoreClientSubscriptionRequest $request)
    {
        return DB::transaction(function () use ($request) {
            $subscription = ClientSubscription::create(array_merge(
                $request->validated(),
                ['status' => 'pending']
            ));
            $subscription->load('client', 'productService');

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
                'document_id' => $document->id,
                'next_bill_date' => $dueDate,
                'invoice_created_at' => now(),
                'reminders_sent' => [],
            ]);

            // Send invoice to client (email + SMS if tenant allows)
            $document->load('items', 'client');
            $client->notify(new InvoiceSentNotification($document));

            return new ClientSubscriptionResource($subscription);
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

    public function destroy(ClientSubscription $clientSubscription)
    {
        $clientSubscription->delete();
        return response()->json(['message' => 'Subscription deleted successfully']);
    }
}

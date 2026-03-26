<?php

namespace App\Http\Controllers\Portal;

use App\Http\Controllers\Controller;
use App\Models\ClientSubscription;
use App\Models\Document;
use App\Models\RecurringInvoiceLog;
use App\Models\Tenant;
use App\Notifications\InvoiceSentNotification;
use App\Services\DocumentNumberService;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class PortalSubscriptionController extends Controller
{
    private const CYCLE_INTERVALS = [
        'monthly' => '1 month',
        'quarterly' => '3 months',
        'half_yearly' => '6 months',
        'yearly' => '1 year',
    ];

    public function index(Request $request)
    {
        $clientId = $request->user()->client_id;

        $subscriptions = ClientSubscription::where('client_id', $clientId)
            ->with('productService:id,name,type,price,billing_cycle')
            ->orderBy('expire_date')
            ->get()
            ->map(function ($sub) {
                $cycle = $sub->productService?->billing_cycle;
                $sub->billing_cycle = $cycle;
                $sub->next_invoice_date = $this->calculateNextDueDate($sub);
                return $sub;
            });

        return response()->json(['data' => $subscriptions]);
    }

    public function generateInvoice(Request $request, ClientSubscription $clientSubscription)
    {
        $clientId = $request->user()->client_id;

        if ($clientSubscription->client_id !== $clientId) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $clientSubscription->load('client', 'productService');
        $client = $clientSubscription->client;
        $product = $clientSubscription->productService;

        if (!$client || !$product) {
            return response()->json(['message' => 'Subscription is missing client or product data.'], 422);
        }

        return DB::transaction(function () use ($clientSubscription, $client, $product) {
            $tenant = Tenant::withoutGlobalScopes()->find($client->tenant_id);
            $qty = $clientSubscription->quantity;

            $lineBase = $qty * (float) $product->price;
            $lineTax = $lineBase * ((float) ($product->tax_percent ?? 0) / 100);
            $lineTotal = $lineBase + $lineTax;

            $description = $product->name;
            if ($clientSubscription->label) {
                $description .= " — {$clientSubscription->label}";
            }

            $document = Document::create([
                'tenant_id' => $tenant->id,
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
                'document_id' => $document->id,
                'next_bill_date' => now(),
                'invoice_created_at' => now(),
                'reminders_sent' => [],
            ]);

            return response()->json([
                'message' => "Invoice {$document->document_number} created.",
                'data' => [
                    'document_id' => $document->id,
                    'document_number' => $document->document_number,
                ],
            ]);
        });
    }

    private function calculateNextDueDate(ClientSubscription $sub): ?string
    {
        $cycle = $sub->productService?->billing_cycle;
        if (!$cycle || $cycle === 'once' || !isset(self::CYCLE_INTERVALS[$cycle])) {
            return null;
        }

        // Use expire_date as the next due date if available
        if ($sub->expire_date) {
            $next = Carbon::parse($sub->expire_date);
            // If expire_date is in the past, walk forward
            $interval = self::CYCLE_INTERVALS[$cycle];
            while ($next->lt(Carbon::today())) {
                $next->add($interval);
            }
            return $next->format('Y-m-d');
        }

        // Fallback: calculate from start_date
        $interval = self::CYCLE_INTERVALS[$cycle];
        $next = Carbon::parse($sub->start_date)->copy();
        while ($next->lte(Carbon::today())) {
            $next->add($interval);
        }

        return $next->format('Y-m-d');
    }
}

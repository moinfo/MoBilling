<?php

namespace App\Http\Controllers\Portal;

use App\Http\Controllers\Controller;
use App\Models\ClientSubscription;
use App\Models\Document;
use App\Models\ProductService;
use App\Models\RecurringInvoiceLog;
use App\Services\DocumentNumberService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

/**
 * Client self-service ordering ("Order New Services").
 * Order -> pending subscription + invoice; payment activates it and — for
 * WHM/cPanel products — auto-provisions the hosting account.
 */
class PortalOrderController extends Controller
{
    /** Grouped product catalog for the shopping-cart page. */
    public function catalog(Request $request)
    {
        $tenantId = $request->user()->tenant_id;

        // WHMCS group ordering, then anything else alphabetically.
        $groupOrder = DB::connection('whmcs')->table('tblproductgroups')->pluck('order', 'name')->all();

        $products = ProductService::withoutGlobalScopes()
            ->where('tenant_id', $tenantId)
            ->where('is_active', true)
            ->where('portal_visible', true)
            ->where('price', '>', 0)
            ->whereNotNull('category')
            ->where('category', '!=', 'Server Sync Tool Auto-Created Products')
            // billing variants (WHMCS-P{id}-{cycle}-{amount}) are internal price
            // records, not catalog entries
            ->where(fn ($q) => $q->whereNull('code')->orWhere('code', 'not like', 'WHMCS-P%-%'))
            ->orderBy('price')
            ->get();

        $groups = $products->groupBy('category')
            ->map(fn ($items, $category) => [
                'name'     => $category,
                'order'    => $groupOrder[$category] ?? 999,
                'products' => $items->map(fn ($p) => [
                    'id'            => $p->id,
                    'name'          => $p->name,
                    'features'      => collect(preg_split('/\r\n|\r|\n/', (string) $p->description))
                                        ->map(fn ($l) => trim($l))->filter()->values(),
                    'price'         => (float) $p->price,
                    'billing_cycle' => $p->billing_cycle,
                    'needs_domain'  => $p->provisioning_type === 'whm_cpanel',
                ])->values(),
            ])
            ->sortBy([['order', 'asc'], ['name', 'asc']])
            ->values();

        return response()->json(['data' => $groups]);
    }

    /** Place an order: pending subscription + invoice to pay. */
    public function store(Request $request)
    {
        $user = $request->user();
        $tenantId = $user->tenant_id;

        $data = $request->validate([
            'product_service_id' => ['required', 'uuid',
                Rule::exists('product_services', 'id')->where('tenant_id', $tenantId)->where('is_active', true)],
            'label' => 'nullable|string|max:255',
        ]);

        $product = ProductService::withoutGlobalScopes()->find($data['product_service_id']);

        if ($product->provisioning_type === 'whm_cpanel' && empty($data['label'])) {
            return response()->json(['message' => 'Please enter the domain for this hosting service.'], 422);
        }

        [$subscription, $document] = DB::transaction(function () use ($user, $tenantId, $product, $data) {
            $start = now()->startOfDay();
            $expire = match ($product->billing_cycle) {
                'monthly'     => $start->copy()->addMonth(),
                'quarterly'   => $start->copy()->addMonths(3),
                'half_yearly' => $start->copy()->addMonths(6),
                'yearly'      => $start->copy()->addYear(),
                default       => null,
            };

            $subscription = ClientSubscription::create([
                'tenant_id'          => $tenantId,
                'client_id'          => $user->client_id,
                'product_service_id' => $product->id,
                'label'              => $data['label'] ?? null,
                'quantity'           => 1,
                'start_date'         => $start,
                'expire_date'        => $expire,
                'status'             => 'pending',
                'metadata'           => array_filter([
                    'portal_order' => true,
                    'domain'       => $product->provisioning_type === 'whm_cpanel' ? strtolower($data['label']) : null,
                ]),
            ]);

            $lineBase = (float) $product->price;
            $lineTax  = $lineBase * ((float) ($product->tax_percent ?? 0) / 100);
            $total    = round($lineBase + $lineTax, 2);

            $document = Document::withoutGlobalScopes()->create([
                'tenant_id'       => $tenantId,
                'client_id'       => $user->client_id,
                'type'            => 'invoice',
                'document_number' => app(DocumentNumberService::class)->generate('invoice', $tenantId),
                'date'            => now()->toDateString(),
                'due_date'        => now()->toDateString(),
                'subtotal'        => round($lineBase, 2),
                'discount_amount' => 0,
                'tax_amount'      => round($lineTax, 2),
                'total'           => $total,
                'status'          => 'sent',
                'notes'           => 'Portal order: new subscription',
            ]);

            $document->items()->create([
                'product_service_id' => $product->id,
                'item_type'          => $product->type,
                'description'        => $product->name . ($data['label'] ? " — {$data['label']}" : ''),
                'quantity'           => 1,
                'price'              => $product->price,
                'tax_percent'        => $product->tax_percent ?? 0,
                'tax_amount'         => round($lineTax, 2),
                'total'              => $total,
            ]);

            // Mark the first cycle as invoiced so the recurring engine doesn't
            // bill it again, and so payment activates this subscription.
            RecurringInvoiceLog::withoutGlobalScopes()->create([
                'tenant_id'              => $tenantId,
                'client_id'              => $user->client_id,
                'product_service_id'     => $product->id,
                'client_subscription_id' => $subscription->id,
                'document_id'            => $document->id,
                'next_bill_date'         => $start->toDateString(),
                'invoice_created_at'     => now(),
                'reminders_sent'         => [],
            ]);

            return [$subscription, $document];
        });

        return response()->json([
            'data'    => [
                'subscription_id' => $subscription->id,
                'document_id'     => $document->id,
                'document_number' => $document->document_number,
                'total'           => (float) $document->total,
            ],
            'message' => "Order placed — pay invoice {$document->document_number} to activate your service" .
                         ($product->provisioning_type === 'whm_cpanel' ? ' (it will be set up automatically after payment)' : '') . '.',
        ], 201);
    }
}

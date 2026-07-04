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

    /** Offered TLDs for the domain chooser dropdown. */
    public function tlds(Request $request)
    {
        $tenantId = $request->user()->tenant_id;

        $rows = \App\Models\DomainTld::where('is_active', true)
            ->where(fn ($q) => $q->where('tenant_id', $tenantId)->orWhereNull('tenant_id'))
            ->orderBy('tld')->orderByRaw('tenant_id IS NULL')
            ->get()->unique('tld')->values()
            ->map(fn ($t) => [
                'tld'            => $t->tld,
                'register_price' => (float) $t->register_price,
                'transfer_price' => (float) $t->transfer_price,
                'years_min'      => $t->years_min,
                'years_max'      => $t->years_max,
            ]);

        return response()->json(['data' => $rows]);
    }

    /** Domain addons offered on the configuration step. */
    public function domainAddons(Request $request)
    {
        $tenantId = $request->user()->tenant_id;

        $rows = DB::table('domain_addons')
            ->where('is_active', true)
            ->where(fn ($q) => $q->where('tenant_id', $tenantId)->orWhereNull('tenant_id'))
            ->orderBy('sort')
            ->get(['id', 'name', 'description', 'price', 'is_free']);

        return response()->json(['data' => $rows]);
    }

    /** Active paid add-ons offered by a product, for the order configuration step. */
    public function productAddons(Request $request, string $product)
    {
        $tenantId = $request->user()->tenant_id;

        $productModel = ProductService::withoutGlobalScopes()
            ->where('tenant_id', $tenantId)
            ->where('id', $product)
            ->first();

        if (!$productModel) {
            return response()->json(['data' => []]);
        }

        $rows = $productModel->addons()
            ->withoutGlobalScopes()
            ->where('product_addons.tenant_id', $tenantId)
            ->where('is_active', true)
            ->orderBy('name')
            ->get(['product_addons.id', 'name', 'description', 'price', 'billing_cycle'])
            ->map(fn ($a) => [
                'id'            => $a->id,
                'name'          => $a->name,
                'description'   => $a->description,
                'price'         => (float) $a->price,
                'billing_cycle' => $a->billing_cycle,
            ]);

        return response()->json(['data' => $rows]);
    }

    /** Place an order: pending subscription + invoice to pay. */
    public function store(Request $request)
    {
        $user = $request->user();
        $tenantId = $user->tenant_id;

        $data = $request->validate([
            'product_service_id' => ['required', 'uuid',
                Rule::exists('product_services', 'id')->where('tenant_id', $tenantId)->where('is_active', true)],
            'label'       => 'nullable|string|max:255',
            'domain_mode' => 'nullable|in:register,transfer,existing',
            'auth_info'   => 'required_if:domain_mode,transfer|nullable|string|max:255',
            'years'       => 'nullable|integer|min:1|max:10',
            'addons'      => 'nullable|array',
            'addons.*'    => 'uuid',
            'product_addon_ids'   => 'nullable|array',
            'product_addon_ids.*' => 'uuid',
        ]);

        $product = ProductService::withoutGlobalScopes()->find($data['product_service_id']);

        // Paid product add-ons: only those this product actually offers, for this tenant.
        $productAddons = collect();
        if (!empty($data['product_addon_ids'])) {
            $productAddons = \App\Models\ProductAddon::withoutGlobalScopes()
                ->where('tenant_id', $tenantId)
                ->where('is_active', true)
                ->whereIn('id', $data['product_addon_ids'])
                ->whereHas('products', fn ($q) => $q->where('product_services.id', $product->id))
                ->get();
        }
        $mode    = $data['domain_mode'] ?? 'existing';
        $domain  = strtolower(trim((string) ($data['label'] ?? '')));

        if ($product->provisioning_type === 'whm_cpanel' && $domain === '') {
            return response()->json(['message' => 'Please enter the domain for this hosting service.'], 422);
        }

        // Bundled domain registration/transfer: validate against the registry
        // and the TLD catalog BEFORE creating anything.
        $domainPricing = null;
        if (in_array($mode, ['register', 'transfer']) && $domain !== '') {
            if (\App\Models\Domain::withoutGlobalScopes()->where('name', $domain)->exists()) {
                return response()->json(['message' => "{$domain} already exists in our system — choose \"use my existing domain\" instead."], 422);
            }
            $tld = strtolower(explode('.', $domain, 2)[1] ?? '');
            $domainPricing = \App\Models\DomainTld::priceFor($tenantId, $tld);
            if (!$domainPricing) {
                return response()->json(['message' => "We don't currently offer .{$tld} — please contact us."], 422);
            }
            $years = (int) ($data['years'] ?? 1);
            if ($years < $domainPricing->years_min || $years > $domainPricing->years_max) {
                return response()->json(['message' => "Registration period must be between {$domainPricing->years_min} and {$domainPricing->years_max} years."], 422);
            }
            try {
                $check = app(\App\Services\Registrar\DomainRegistrarManager::class)->driverFor($tenantId)->check($domain);
                if ($mode === 'register' && !$check['available']) {
                    return response()->json(['message' => "{$domain} is not available to register."], 422);
                }
                if ($mode === 'transfer' && $check['available']) {
                    return response()->json(['message' => "{$domain} is not registered — nothing to transfer."], 422);
                }
            } catch (\App\Exceptions\RegistrarApiException) {
                return response()->json(['message' => 'Could not verify the domain right now — please try again.'], 422);
            }
        }

        $years  = (int) ($data['years'] ?? 1);
        $addons = collect();
        if (!empty($data['addons']) && in_array($mode, ['register', 'transfer'])) {
            $addons = DB::table('domain_addons')->where('is_active', true)
                ->where(fn ($q) => $q->where('tenant_id', $tenantId)->orWhereNull('tenant_id'))
                ->whereIn('id', $data['addons'])->get();
        }

        [$subscription, $document] = DB::transaction(function () use ($user, $tenantId, $product, $data, $mode, $domain, $domainPricing, $years, $addons, $productAddons) {
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
            $domainPrice = 0.0;
            if ($domainPricing && in_array($mode, ['register', 'transfer'])) {
                $unit = (float) ($mode === 'register' ? $domainPricing->register_price : $domainPricing->transfer_price);
                $domainPrice = round($unit * $years, 2);
            }
            $addonsPrice = round((float) $addons->sum(fn ($a) => $a->is_free ? 0 : $a->price), 2);

            // Paid product add-ons: each is its own base + tax line.
            $productAddonsBase = round((float) $productAddons->sum(fn ($a) => (float) $a->price), 2);
            $productAddonsTax  = round((float) $productAddons->sum(
                fn ($a) => (float) $a->price * ((float) ($a->tax_percent ?? 0) / 100)
            ), 2);

            $total = round($lineBase + $lineTax + $domainPrice + $addonsPrice + $productAddonsBase + $productAddonsTax, 2);

            $document = Document::withoutGlobalScopes()->create([
                'tenant_id'       => $tenantId,
                'client_id'       => $user->client_id,
                'type'            => 'invoice',
                'document_number' => app(DocumentNumberService::class)->generate('invoice', $tenantId),
                'date'            => now()->toDateString(),
                'due_date'        => now()->toDateString(),
                'subtotal'        => round($lineBase + $domainPrice + $addonsPrice + $productAddonsBase, 2),
                'discount_amount' => 0,
                'tax_amount'      => round($lineTax + $productAddonsTax, 2),
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
                'total'              => round($lineBase + $lineTax, 2),
            ]);

            foreach ($productAddons as $addon) {
                $addonTax = round((float) $addon->price * ((float) ($addon->tax_percent ?? 0) / 100), 2);
                $document->items()->create([
                    'item_type'   => 'service',
                    'description' => "Add-on: {$addon->name}" . ($data['label'] ? " — {$data['label']}" : ''),
                    'quantity'    => 1,
                    'price'       => $addon->price,
                    'tax_percent' => $addon->tax_percent ?? 0,
                    'tax_amount'  => $addonTax,
                    'total'       => round((float) $addon->price + $addonTax, 2),
                ]);
            }

            if ($domainPricing && in_array($mode, ['register', 'transfer'])) {
                $document->items()->create([
                    'item_type'   => 'service',
                    'description' => ucfirst($mode) . " domain {$domain} — {$years} year(s)",
                    'quantity'    => $years,
                    'price'       => round($domainPrice / max($years, 1), 2),
                    'tax_percent' => 0,
                    'tax_amount'  => 0,
                    'total'       => $domainPrice,
                ]);

                foreach ($addons as $addon) {
                    if (!$addon->is_free && (float) $addon->price > 0) {
                        $document->items()->create([
                            'item_type'   => 'service',
                            'description' => "{$addon->name} — {$domain}",
                            'quantity'    => 1,
                            'price'       => $addon->price,
                            'tax_percent' => 0,
                            'tax_amount'  => 0,
                            'total'       => $addon->price,
                        ]);
                    }
                }

                \App\Models\Domain::create([
                    'tenant_id'            => $tenantId,
                    'client_id'            => $user->client_id,
                    'registrar_account_id' => app(\App\Services\Registrar\DomainRegistrarManager::class)->accountFor($tenantId)->id,
                    'name'                 => $domain,
                    'status'               => 'pending',
                    'auto_renew'           => true,
                    'epp_auth_info'        => $data['auth_info'] ?? null,
                    'client_subscription_id' => $subscription->id,
                    'meta'                 => [
                        'pending_action'    => $mode,
                        'pending_years'     => $years,
                        'order_document_id' => $document->id,
                        'portal_order'      => true,
                        'addons'            => $addons->pluck('name')->values()->all(),
                    ],
                ]);
            }

            // Paid product add-ons: remember what was ordered so payment
            // (DocumentObserver) can attach them to the live service. Snapshot
            // is taken at activation from the current add-on catalog rows.
            if ($productAddons->isNotEmpty()) {
                $meta = $subscription->metadata ?? [];
                $meta['pending_addons'] = [
                    'document_id' => $document->id,
                    'addon_ids'   => $productAddons->pluck('id')->values()->all(),
                ];
                $subscription->update(['metadata' => $meta]);
            }

            // Mark the first cycle as invoiced so the recurring engine doesn't
            // bill it again, and so payment activates this subscription.
            // updateOrCreate: the (tenant, client, product, date) unique key may
            // already hold a historical row (e.g. seeded WHMCS history) — the
            // newest order takes over the linkage so payment activates THIS sub.
            RecurringInvoiceLog::withoutGlobalScopes()->updateOrCreate(
                [
                    'tenant_id'          => $tenantId,
                    'client_id'          => $user->client_id,
                    'product_service_id' => $product->id,
                    'next_bill_date'     => $start->toDateString(),
                ],
                [
                    'client_subscription_id' => $subscription->id,
                    'document_id'            => $document->id,
                    'invoice_created_at'     => now(),
                    'reminders_sent'         => [],
                ]
            );

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

<?php

namespace App\Services;

use App\Models\Client;
use App\Models\ClientSubscription;
use App\Models\Coupon;
use App\Models\CouponRedemption;
use App\Models\Document;
use App\Models\ProductService;
use App\Models\RecurringInvoiceLog;
use App\Models\Tenant;
use App\Notifications\InvoiceSentNotification;
use App\Notifications\RecurringInvoiceReminderNotification;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

class RecurringInvoiceService
{
    public const REMINDER_DAYS = [21, 14, 7, 3, 1];

    private const CYCLE_INTERVALS = [
        'monthly' => '1 month',
        'quarterly' => '3 months',
        'half_yearly' => '6 months',
        'yearly' => '1 year',
    ];

    public function processAll(): array
    {
        $invoices = $this->processUpcomingBills();
        $dayOfMonth = $this->processDayOfMonthBills();
        $reminders = $this->processReminders();

        return [
            'invoices_created' => $invoices['created'] + $dayOfMonth['created'],
            'invoices_failed' => $invoices['failed'] + $dayOfMonth['failed'],
            'reminders_sent' => $reminders['sent'],
            'reminders_failed' => $reminders['failed'],
        ];
    }

    /**
     * Find active subscriptions whose next bill date falls within 30 days,
     * group by client, and create one invoice per client.
     */
    private function processUpcomingBills(): array
    {
        $today = Carbon::today();
        $targetDate = $today->copy()->addDays(30);
        $count = 0;
        $failed = 0;

        $subscriptions = ClientSubscription::withoutGlobalScopes()
            ->where('status', 'active')
            // Parallel mode: WHMCS still bills its own (imported) subscriptions.
            ->when(config('whmcs.parallel_mode'), fn ($q) => $q->whereNull('legacy_id'))
            ->with(['productService', 'client',
                'addons' => fn ($q) => $q->where('status', 'active'),
                'configOptions' => fn ($q) => $q->where('status', 'active')])
            ->whereHas('productService', fn ($q) => $q
                ->where('is_active', true)
                ->whereNotNull('billing_cycle')
                ->where('billing_cycle', '!=', 'once')
                // Day-of-month products are billed by processDayOfMonthBills()
                // instead — excluded here so they're never invoiced twice.
                ->whereNull('invoice_day_of_month')
            )
            ->get();

        // Calculate next bill date for each subscription and filter to 30-day window
        $dueSubscriptions = [];
        foreach ($subscriptions as $sub) {
            $interval = self::CYCLE_INTERVALS[$sub->productService->billing_cycle] ?? null;
            if (!$interval) {
                continue;
            }

            $nextBillDate = $this->calculateNextBillDate($sub->start_date, $interval, $today);
            if (!$nextBillDate || $nextBillDate->gt($targetDate)) {
                continue;
            }

            // Check if already logged for this cycle
            $exists = RecurringInvoiceLog::withoutGlobalScopes()
                ->where('tenant_id', $sub->tenant_id)
                ->where('client_id', $sub->client_id)
                ->where('product_service_id', $sub->product_service_id)
                ->where('next_bill_date', $nextBillDate->format('Y-m-d'))
                ->exists();

            if ($exists) {
                continue;
            }

            // Calculate service period: from previous bill date to day before next bill date
            $interval = self::CYCLE_INTERVALS[$sub->productService->billing_cycle];
            $serviceFrom = $nextBillDate->copy()->sub($interval);
            $serviceTo = $nextBillDate->copy()->subDay();

            $dueSubscriptions[] = [
                'subscription' => $sub,
                'next_bill_date' => $nextBillDate,
                'service_from' => $serviceFrom,
                'service_to' => $serviceTo,
            ];
        }

        // Group by tenant+client so we create one invoice per client
        $grouped = collect($dueSubscriptions)->groupBy(
            fn ($item) => $item['subscription']->tenant_id . '|' . $item['subscription']->client_id
        );

        foreach ($grouped as $items) {
            $firstSub = $items->first()['subscription'];

            try {
                $tenant = Tenant::find($firstSub->tenant_id);
                if (!$tenant || !$tenant->hasAccess()) {
                    continue;
                }

                $client = Client::withoutGlobalScopes()->find($firstSub->client_id);
                if (!$client) {
                    continue;
                }

                // Find the latest due date among the group (invoice due date)
                $latestDueDate = $items->max(fn ($item) => $item['next_bill_date']->timestamp);
                $invoiceDueDate = Carbon::createFromTimestamp($latestDueDate);

                $document = $this->createInvoice($tenant, $client, $items->all(), $invoiceDueDate);

                // Log each subscription
                foreach ($items as $item) {
                    RecurringInvoiceLog::withoutGlobalScopes()->create([
                        'tenant_id' => $tenant->id,
                        'client_id' => $client->id,
                        'product_service_id' => $item['subscription']->product_service_id,
                        'client_subscription_id' => $item['subscription']->id,
                        'document_id' => $document->id,
                        'next_bill_date' => $item['next_bill_date'],
                        'invoice_created_at' => now(),
                        'reminders_sent' => [],
                    ]);
                }

                $count++;
            } catch (\Throwable $e) {
                $failed++;
                Log::error('RecurringInvoice: failed to create invoice', [
                    'tenant_id' => $firstSub->tenant_id,
                    'client_id' => $firstSub->client_id,
                    'exception' => $e,
                ]);
            }
        }

        return ['created' => $count, 'failed' => $failed];
    }

    /**
     * A second billing model alongside cycle-based subscriptions
     * (processUpcomingBills): some contracts (e.g. a monthly retainer) need
     * a FIXED calendar issue date every month — e.g. always invoice on the
     * 25th — rather than "N days before the renewal date". Opt-in via
     * ProductService.invoice_day_of_month; due_date is always the last day
     * of the invoicing month, so it lands the day before the 1st
     * regardless of the month's length (28-31 days) — no manual date math
     * needed per month. Runs only on the matching day, one invoice per
     * client per calendar month (RecurringInvoiceLog keyed on that due
     * date is the idempotency guard against a double run).
     */
    private function processDayOfMonthBills(): array
    {
        $today = Carbon::today();
        $count = 0;
        $failed = 0;

        $subscriptions = ClientSubscription::withoutGlobalScopes()
            ->where('status', 'active')
            ->when(config('whmcs.parallel_mode'), fn ($q) => $q->whereNull('legacy_id'))
            ->with('productService')
            ->whereHas('productService', fn ($q) => $q
                ->where('is_active', true)
                ->where('invoice_day_of_month', $today->day)
            )
            ->get();

        if ($subscriptions->isEmpty()) {
            return ['created' => 0, 'failed' => 0];
        }

        $dueDate = $today->copy()->endOfMonth();
        $periodStart = $today->copy()->startOfMonth();

        $grouped = $subscriptions->groupBy(fn ($sub) => $sub->tenant_id . '|' . $sub->client_id);

        foreach ($grouped as $subsForClient) {
            $firstSub = $subsForClient->first();

            $alreadyInvoiced = RecurringInvoiceLog::withoutGlobalScopes()
                ->where('tenant_id', $firstSub->tenant_id)
                ->where('client_id', $firstSub->client_id)
                ->whereIn('product_service_id', $subsForClient->pluck('product_service_id'))
                ->where('next_bill_date', $dueDate->format('Y-m-d'))
                ->exists();
            if ($alreadyInvoiced) {
                continue;
            }

            try {
                $tenant = Tenant::find($firstSub->tenant_id);
                if (!$tenant || !$tenant->hasAccess()) {
                    continue;
                }

                $client = Client::withoutGlobalScopes()->find($firstSub->client_id);
                if (!$client) {
                    continue;
                }

                $billItems = $subsForClient->map(fn ($sub) => [
                    'subscription' => $sub,
                    'service_from' => $periodStart->copy(),
                    'service_to'   => $dueDate->copy(),
                ])->all();

                $document = $this->createInvoice($tenant, $client, $billItems, $dueDate);

                foreach ($subsForClient as $sub) {
                    RecurringInvoiceLog::withoutGlobalScopes()->create([
                        'tenant_id'              => $tenant->id,
                        'client_id'              => $client->id,
                        'product_service_id'     => $sub->product_service_id,
                        'client_subscription_id' => $sub->id,
                        'document_id'            => $document->id,
                        'next_bill_date'         => $dueDate,
                        'invoice_created_at'     => now(),
                        'reminders_sent'         => [],
                    ]);
                }

                $count++;
            } catch (\Throwable $e) {
                $failed++;
                Log::error('RecurringInvoice (day-of-month): failed to create invoice', [
                    'tenant_id' => $firstSub->tenant_id,
                    'client_id' => $firstSub->client_id,
                    'exception' => $e,
                ]);
            }
        }

        return ['created' => $count, 'failed' => $failed];
    }

    /**
     * Calculate the next bill date from a start date + interval that is >= today.
     */
    private function calculateNextBillDate(Carbon $startDate, string $interval, Carbon $today): ?Carbon
    {
        $date = $startDate->copy();

        // Walk forward until we find the next date that's >= today
        while ($date->lt($today)) {
            $date->add($interval);
        }

        return $date;
    }

    /**
     * The pricing/coupon/add-on/config-option math shared by createInvoice()
     * (persists) and previewForSubscription() (doesn't) — kept as one method
     * so a manual "generate invoice" action can never compute a different
     * total than what actually gets billed.
     */
    private function buildLineItems(array $items): array
    {
        $subtotal = 0;
        $taxAmount = 0;
        $discountTotal = 0;
        $lineItems = [];
        $renewalRedemptions = []; // [coupon, client_id, discount] to audit after the doc exists

        foreach ($items as $item) {
                $sub = $item['subscription'];
                $product = $sub->productService;
                $qty = $sub->quantity;

                $lineBase = $qty * (float) $product->price;

                // Recurring coupon: re-apply the discount on each renewal cycle,
                // re-checking the coupon is still active + within its window. The
                // discount reduces the taxable base, consistent with the order.
                // Renewals do NOT consume the coupon's max_uses order quota.
                $lineDiscount = 0.0;
                $applied = is_array($sub->metadata ?? null) ? ($sub->metadata['applied_coupon'] ?? null) : null;
                $renewalCoupon = null;
                if (is_array($applied) && !empty($applied['recurring']) && !empty($applied['coupon_id'])) {
                    $renewalCoupon = Coupon::withoutGlobalScopes()
                        ->where('tenant_id', $sub->tenant_id)
                        ->whereKey($applied['coupon_id'])
                        ->first();
                    if ($renewalCoupon && $renewalCoupon->recurring && $renewalCoupon->isRedeemable()) {
                        $lineDiscount = round(min((float) $renewalCoupon->discountFor($lineBase, $product), $lineBase), 2);
                    }
                }

                $netBase = round($lineBase - $lineDiscount, 2);
                $lineTax = $netBase * ((float) ($product->tax_percent ?? 0) / 100);
                $lineTotal = $netBase + $lineTax;

                $description = $product->name;
                if ($sub->label) {
                    $description .= " — {$sub->label}";
                }
                if ($lineDiscount > 0 && $renewalCoupon) {
                    $description .= " (promo {$renewalCoupon->code})";
                }

                $lineItems[] = [
                    'product_service_id' => $product->id,
                    'item_type' => $product->type,
                    'description' => $description,
                    'quantity' => $qty,
                    'price' => $product->price,
                    'discount_type' => $renewalCoupon && $lineDiscount > 0 ? $renewalCoupon->type : 'percent',
                    'discount_value' => $renewalCoupon && $lineDiscount > 0 ? (float) $renewalCoupon->value : 0,
                    'tax_percent' => $product->tax_percent ?? 0,
                    'tax_amount' => round($lineTax, 2),
                    'total' => round($lineTotal, 2),
                    'unit' => $product->unit,
                    'service_from' => $item['service_from']->format('Y-m-d'),
                    'service_to' => $item['service_to']->format('Y-m-d'),
                ];

                $subtotal += $lineBase;
                $taxAmount += $lineTax;
                $discountTotal += $lineDiscount;
                if ($lineDiscount > 0 && $renewalCoupon) {
                    $renewalRedemptions[] = ['coupon' => $renewalCoupon, 'client_id' => $sub->client_id, 'discount' => $lineDiscount];
                }

                // Paid product add-ons attached to this service. Bill each active
                // add-on whose cycle matches the product renewal cycle (so a
                // monthly add-on isn't wrongly billed on a yearly renewal, and to
                // avoid double-adding across cycles). Snapshot price is used.
                foreach ($sub->addons as $addon) {
                    if ($addon->status !== 'active' || $addon->billing_cycle !== $product->billing_cycle) {
                        continue;
                    }

                    $addonBase = $qty * (float) $addon->price;
                    $addonTax = $addonBase * ((float) ($addon->tax_percent ?? 0) / 100);

                    $lineItems[] = [
                        'item_type' => 'service',
                        'description' => "Add-on: {$addon->name}" . ($sub->label ? " — {$sub->label}" : ''),
                        'quantity' => $qty,
                        'price' => $addon->price,
                        'discount_type' => 'percent',
                        'discount_value' => 0,
                        'tax_percent' => $addon->tax_percent ?? 0,
                        'tax_amount' => round($addonTax, 2),
                        'total' => round($addonBase + $addonTax, 2),
                        'service_from' => $item['service_from']->format('Y-m-d'),
                        'service_to' => $item['service_to']->format('Y-m-d'),
                    ];

                    $subtotal += $addonBase;
                    $taxAmount += $addonTax;
                }

                // Configurable options attached to this service. Bill each active
                // option whose cycle matches the product renewal cycle (so an
                // option isn't wrongly billed on a mismatched renewal). Snapshot
                // price/quantity is used. Product quantity multiplies through.
                foreach ($sub->configOptions as $configOption) {
                    if ($configOption->status !== 'active' || $configOption->billing_cycle !== $product->billing_cycle) {
                        continue;
                    }

                    $optBase = $qty * (float) $configOption->unit_price * (int) $configOption->quantity;
                    $optTax = $optBase * ((float) ($configOption->tax_percent ?? 0) / 100);

                    $lineItems[] = [
                        'item_type' => 'service',
                        'description' => "Option: {$configOption->label}" . ($sub->label ? " — {$sub->label}" : ''),
                        'quantity' => $qty * (int) $configOption->quantity,
                        'price' => $configOption->unit_price,
                        'discount_type' => 'percent',
                        'discount_value' => 0,
                        'tax_percent' => $configOption->tax_percent ?? 0,
                        'tax_amount' => round($optTax, 2),
                        'total' => round($optBase + $optTax, 2),
                        'service_from' => $item['service_from']->format('Y-m-d'),
                        'service_to' => $item['service_to']->format('Y-m-d'),
                    ];

                    $subtotal += $optBase;
                    $taxAmount += $optTax;
                }
            }
        return [
            'line_items' => $lineItems,
            'subtotal' => round($subtotal, 2),
            'tax_amount' => round($taxAmount, 2),
            'discount_amount' => round($discountTotal, 2),
            'total' => round($subtotal - $discountTotal + $taxAmount, 2),
            'renewal_redemptions' => $renewalRedemptions,
        ];
    }

    /**
     * Create an invoice for one client with multiple subscription line items.
     */
    private function createInvoice(Tenant $tenant, Client $client, array $items, Carbon $dueDate): Document
    {
        $document = DB::transaction(function () use ($tenant, $client, $items, $dueDate) {
            $docNumber = app(DocumentNumberService::class)->generate('invoice', $tenant->id);
            $built = $this->buildLineItems($items);

            $document = Document::withoutGlobalScopes()->create([
                'tenant_id' => $tenant->id,
                'client_id' => $client->id,
                'type' => 'invoice',
                'document_number' => $docNumber,
                'date' => now()->format('Y-m-d'),
                'due_date' => $dueDate->format('Y-m-d'),
                'subtotal' => $built['subtotal'],
                'discount_amount' => $built['discount_amount'],
                'tax_amount' => $built['tax_amount'],
                'total' => $built['total'],
                'notes' => 'Auto-generated recurring invoice',
                'status' => 'sent',
            ]);

            foreach ($built['line_items'] as $lineItem) {
                $document->items()->create($lineItem);
            }

            // Audit each recurring-coupon discount applied on this renewal.
            foreach ($built['renewal_redemptions'] as $r) {
                CouponRedemption::withoutGlobalScopes()->create([
                    'tenant_id'       => $r['coupon']->tenant_id,
                    'coupon_id'       => $r['coupon']->id,
                    'client_id'       => $r['client_id'],
                    'document_id'     => $document->id,
                    'discount_amount' => round($r['discount'], 2),
                ]);
            }

            $document->load('items', 'client');

            return $document;
        });

        // Send to client (email + SMS if tenant allows) AFTER the transaction commits,
        // so an async queue cannot pick up the job before the invoice row is persisted.
        try {
            $client->notifyNow(new InvoiceSentNotification($document));
        } catch (\Throwable $e) {
            Log::error('RecurringInvoice: invoice created but send failed', [
                'document_id' => $document->id,
                'exception' => $e,
            ]);
        }

        return $document;
    }

    /**
     * The per-subscription due date + service period a manual invoice would
     * use — same rules calculateNextBillDate()/the day-of-month path apply
     * for the automated job, just computed on demand for one subscription.
     */
    private function billingWindowFor(ClientSubscription $sub): array
    {
        $product = $sub->productService;
        $interval = self::CYCLE_INTERVALS[$product->billing_cycle] ?? null;
        $today = Carbon::today();

        if ($product->invoice_day_of_month) {
            $dueDate = $today->copy()->endOfMonth();
            $serviceFrom = $today->copy()->startOfMonth();
            $serviceTo = $dueDate->copy();
        } elseif ($interval) {
            $dueDate = $this->calculateNextBillDate($sub->start_date, $interval, $today);
            $serviceFrom = $dueDate->copy()->sub($interval);
            $serviceTo = $dueDate->copy()->subDay();
        } else {
            // One-off / no cycle — bill for today, no meaningful service period.
            $dueDate = $today->copy();
            $serviceFrom = $today->copy();
            $serviceTo = $today->copy();
        }

        return compact('dueDate', 'serviceFrom', 'serviceTo');
    }

    /**
     * Compute what a manually-triggered renewal invoice would look like for
     * one or more subscriptions of the SAME client (e.g. a domain plus its
     * hosting plan — hosting renewal isn't complete without the domain, so
     * the Hosting Accounts "generate invoice" action bundles both into one
     * invoice, same as the automated job groups everything due for a client
     * into a single invoice), without creating anything — same math
     * buildLineItems() uses for the real thing, so the preview can never
     * drift from what actually gets billed.
     *
     * @param ClientSubscription[] $subs
     */
    public function previewForSubscriptions(array $subs): array
    {
        $items = [];
        $dueDates = [];

        foreach ($subs as $sub) {
            $sub->loadMissing(['productService', 'addons', 'configOptions']);
            if (!$sub->productService) {
                continue;
            }
            $window = $this->billingWindowFor($sub);
            $items[] = ['subscription' => $sub, 'service_from' => $window['serviceFrom'], 'service_to' => $window['serviceTo']];
            $dueDates[] = $window['dueDate'];
        }

        if (empty($items)) {
            throw new \RuntimeException('No billable subscription (with a product) found — cannot price an invoice.');
        }

        $built = $this->buildLineItems($items);
        // Latest due date among the group — same convention processUpcomingBills() uses.
        $built['due_date'] = collect($dueDates)->max()->format('Y-m-d');

        return $built;
    }

    /**
     * Manually generate the renewal invoice for one or more subscriptions of
     * the same client — the same createInvoice() the automated job uses,
     * just triggered on demand for subscriptions the automated pass missed
     * (e.g. a broken hosting-account link masked it — see
     * PlanChangeService's domain-fallback fix). Logs one RecurringInvoiceLog
     * entry per subscription against the same document, exactly like the
     * automated grouped-invoice path does, so the "latest invoice" lookup
     * picks it up for each of them immediately.
     *
     * @param ClientSubscription[] $subs
     */
    public function generateForSubscriptions(array $subs): Document
    {
        $preview = $this->previewForSubscriptions($subs);
        $first = $subs[array_key_first($subs)];
        $tenant = Tenant::find($first->tenant_id);
        $client = Client::withoutGlobalScopes()->find($first->client_id);
        if (!$tenant || !$client) {
            throw new \RuntimeException('Tenant or client not found for this subscription.');
        }

        $dueDate = Carbon::parse($preview['due_date']);
        $items = [];
        foreach ($subs as $sub) {
            if (!$sub->productService) {
                continue;
            }
            $product = $sub->productService;
            $serviceFrom = $product->invoice_day_of_month
                ? Carbon::today()->startOfMonth()
                : $dueDate->copy()->sub(self::CYCLE_INTERVALS[$product->billing_cycle] ?? '1 year');
            $serviceTo = $product->invoice_day_of_month ? $dueDate->copy() : $dueDate->copy()->subDay();
            $items[] = ['subscription' => $sub, 'service_from' => $serviceFrom, 'service_to' => $serviceTo];
        }

        $document = $this->createInvoice($tenant, $client, $items, $dueDate);

        foreach ($items as $item) {
            $sub = $item['subscription'];
            RecurringInvoiceLog::withoutGlobalScopes()->create([
                'tenant_id'              => $tenant->id,
                'client_id'              => $client->id,
                'product_service_id'     => $sub->product_service_id,
                'client_subscription_id' => $sub->id,
                'document_id'            => $document->id,
                'next_bill_date'         => $dueDate,
                'invoice_created_at'     => now(),
                'reminders_sent'         => [],
            ]);
        }

        return $document;
    }

    /**
     * Send reminders for unpaid auto-invoices at 21, 14, 7, 3, 1 days before due.
     */
    private function processReminders(): array
    {
        $today = Carbon::today();
        $count = 0;
        $failed = 0;

        $logs = RecurringInvoiceLog::withoutGlobalScopes()
            ->whereNotNull('document_id')
            ->whereNotNull('invoice_created_at')
            // Parallel mode: WHMCS sends its own reminders for imported invoices.
            ->when(config('whmcs.parallel_mode'), fn ($q) => $q
                ->whereHas('document', fn ($d) => $d->whereNull('legacy_id')))
            ->get();

        // Deduplicate by document_id so we only remind once per invoice
        $processed = [];

        foreach ($logs as $log) {
            if (isset($processed[$log->document_id])) {
                continue;
            }

            $daysUntilDue = (int) $today->diffInDays($log->next_bill_date, false);

            if ($daysUntilDue < 0 || !in_array($daysUntilDue, self::REMINDER_DAYS)) {
                continue;
            }

            $alreadySent = $log->reminders_sent ?? [];
            if (in_array($daysUntilDue, $alreadySent)) {
                continue;
            }

            $document = Document::withoutGlobalScopes()->find($log->document_id);
            // A cancelled invoice is not owed — reminding the client to pay
            // one right after telling them it was cancelled is confusing and
            // wrong (real incident: WHMCS-1339 got a cancellation notice on
            // 07 Aug, then a "pay this soon" reminder on 11 Aug).
            if (!$document || in_array($document->status, ['paid', 'cancelled'])) {
                continue;
            }

            try {
                $tenant = Tenant::find($log->tenant_id);
                if (!$tenant || !$tenant->hasAccess()) {
                    continue;
                }

                $client = Client::withoutGlobalScopes()->find($log->client_id);
                if (!$client) {
                    continue;
                }

                $client->notify(new RecurringInvoiceReminderNotification(
                    $document,
                    $tenant,
                    $daysUntilDue
                ));

                // Update all logs for this document
                RecurringInvoiceLog::withoutGlobalScopes()
                    ->where('document_id', $log->document_id)
                    ->get()
                    ->each(function ($l) use ($daysUntilDue) {
                        $sent = $l->reminders_sent ?? [];
                        $sent[] = $daysUntilDue;
                        $l->reminders_sent = $sent;
                        $l->save();
                    });

                $processed[$log->document_id] = true;
                $count++;
            } catch (\Throwable $e) {
                $failed++;
                Log::error('RecurringInvoice: failed to send reminder', [
                    'log_id' => $log->id,
                    'days_remaining' => $daysUntilDue,
                    'exception' => $e,
                ]);
            }
        }

        return ['sent' => $count, 'failed' => $failed];
    }
}

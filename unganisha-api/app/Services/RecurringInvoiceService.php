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
    private const REMINDER_DAYS = [21, 14, 7, 3, 1];

    private const CYCLE_INTERVALS = [
        'monthly' => '1 month',
        'quarterly' => '3 months',
        'half_yearly' => '6 months',
        'yearly' => '1 year',
    ];

    public function processAll(): array
    {
        $invoices = $this->processUpcomingBills();
        $reminders = $this->processReminders();

        return [
            'invoices_created' => $invoices['created'],
            'invoices_failed' => $invoices['failed'],
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
     * Create an invoice for one client with multiple subscription line items.
     */
    private function createInvoice(Tenant $tenant, Client $client, array $items, Carbon $dueDate): Document
    {
        $document = DB::transaction(function () use ($tenant, $client, $items, $dueDate) {
            $docNumber = app(DocumentNumberService::class)->generate('invoice', $tenant->id);

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

            $document = Document::withoutGlobalScopes()->create([
                'tenant_id' => $tenant->id,
                'client_id' => $client->id,
                'type' => 'invoice',
                'document_number' => $docNumber,
                'date' => now()->format('Y-m-d'),
                'due_date' => $dueDate->format('Y-m-d'),
                'subtotal' => round($subtotal, 2),
                'discount_amount' => round($discountTotal, 2),
                'tax_amount' => round($taxAmount, 2),
                'total' => round($subtotal - $discountTotal + $taxAmount, 2),
                'notes' => 'Auto-generated recurring invoice',
                'status' => 'sent',
            ]);

            foreach ($lineItems as $lineItem) {
                $document->items()->create($lineItem);
            }

            // Audit each recurring-coupon discount applied on this renewal.
            foreach ($renewalRedemptions as $r) {
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
            if (!$document || $document->status === 'paid') {
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

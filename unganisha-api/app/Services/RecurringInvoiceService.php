<?php

namespace App\Services;

use App\Models\Client;
use App\Models\ClientSubscription;
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
        $invoicesCreated = $this->processUpcomingBills();
        $remindersSent = $this->processReminders();

        return [
            'invoices_created' => $invoicesCreated,
            'reminders_sent' => $remindersSent,
        ];
    }

    /**
     * Find active subscriptions whose next bill date falls within 30 days,
     * group by client, and create one invoice per client.
     */
    private function processUpcomingBills(): int
    {
        $today = Carbon::today();
        $targetDate = $today->copy()->addDays(30);
        $count = 0;

        $subscriptions = ClientSubscription::withoutGlobalScopes()
            ->where('status', 'active')
            ->with(['productService', 'client'])
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

            $dueSubscriptions[] = [
                'subscription' => $sub,
                'next_bill_date' => $nextBillDate,
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
                        'document_id' => $document->id,
                        'next_bill_date' => $item['next_bill_date'],
                        'invoice_created_at' => now(),
                        'reminders_sent' => [],
                    ]);
                }

                $count++;
            } catch (\Throwable $e) {
                Log::error('RecurringInvoice: failed to create invoice', [
                    'tenant_id' => $firstSub->tenant_id,
                    'client_id' => $firstSub->client_id,
                    'error' => $e->getMessage(),
                ]);
            }
        }

        return $count;
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
        return DB::transaction(function () use ($tenant, $client, $items, $dueDate) {
            $docNumber = app(DocumentNumberService::class)->generate('invoice', $tenant->id);

            $subtotal = 0;
            $taxAmount = 0;
            $lineItems = [];

            foreach ($items as $item) {
                $sub = $item['subscription'];
                $product = $sub->productService;
                $qty = $sub->quantity;

                $lineBase = $qty * (float) $product->price;
                $lineTax = $lineBase * ((float) ($product->tax_percent ?? 0) / 100);
                $lineTotal = $lineBase + $lineTax;

                $description = $product->name;
                if ($sub->label) {
                    $description .= " — {$sub->label}";
                }

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

                $subtotal += $lineBase;
                $taxAmount += $lineTax;
            }

            $document = Document::withoutGlobalScopes()->create([
                'tenant_id' => $tenant->id,
                'client_id' => $client->id,
                'type' => 'invoice',
                'document_number' => $docNumber,
                'date' => now()->format('Y-m-d'),
                'due_date' => $dueDate->format('Y-m-d'),
                'subtotal' => round($subtotal, 2),
                'discount_amount' => 0,
                'tax_amount' => round($taxAmount, 2),
                'total' => round($subtotal + $taxAmount, 2),
                'notes' => 'Auto-generated recurring invoice',
                'status' => 'sent',
            ]);

            foreach ($lineItems as $lineItem) {
                $document->items()->create($lineItem);
            }

            // Send to client (email + SMS if tenant allows)
            $document->load('items', 'client');
            $client->notify(new InvoiceSentNotification($document));

            return $document;
        });
    }

    /**
     * Send reminders for unpaid auto-invoices at 21, 14, 7, 3, 1 days before due.
     */
    private function processReminders(): int
    {
        $today = Carbon::today();
        $count = 0;

        $logs = RecurringInvoiceLog::withoutGlobalScopes()
            ->whereNotNull('document_id')
            ->whereNotNull('invoice_created_at')
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
                Log::error('RecurringInvoice: failed to send reminder', [
                    'log_id' => $log->id,
                    'days_remaining' => $daysUntilDue,
                    'error' => $e->getMessage(),
                ]);
            }
        }

        return $count;
    }
}

<?php

namespace App\Console\Commands;

use App\Models\CronLog;
use App\Models\Document;
use App\Models\Tenant;
use App\Notifications\InvoiceLateFeeNotification;
use App\Notifications\InvoiceOverdueReminderNotification;
use App\Notifications\InvoiceTerminationWarningNotification;
use Carbon\Carbon;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Log;

class ProcessOverdueInvoices extends Command
{
    protected $signature = 'invoices:process-overdue';

    protected $description = 'Process overdue invoices: apply late fees, send reminders, and termination warnings';

    public function handle(): int
    {
        $startedAt = now();
        $today = Carbon::today();

        $lateFees = 0;
        $reminders7d = 0;
        $terminationWarnings = 0;

        try {
            // Get all unpaid invoices that are past due
            $overdueInvoices = Document::withoutGlobalScopes()
                ->where('type', 'invoice')
                ->whereNotIn('status', ['paid', 'draft'])
                ->whereNotNull('due_date')
                ->where('due_date', '<', $today->toDateString())
                ->with('client')
                ->get();

            foreach ($overdueInvoices as $document) {
                $daysOverdue = (int) $document->due_date->diffInDays($today);
                $client = $document->client;
                $tenant = Tenant::find($document->tenant_id);

                if (!$client || !$tenant || !$tenant->hasAccess()) {
                    continue;
                }

                // Update status to overdue if still "sent"
                if ($document->status === 'sent') {
                    $document->update(['status' => 'overdue']);
                }

                // Stage 1: Day 1 overdue — Apply 10% late fee (once)
                if (!$document->overdue_stage) {
                    $lateFeeAmount = round((float) $document->total * 0.10, 2);
                    $newTotal = round((float) $document->total + $lateFeeAmount, 2);

                    // Add late fee line item
                    $document->items()->create([
                        'product_service_id' => null,
                        'item_type' => 'service',
                        'description' => 'Late payment fee (10%)',
                        'quantity' => 1,
                        'price' => $lateFeeAmount,
                        'discount_type' => 'percent',
                        'discount_value' => 0,
                        'tax_percent' => 0,
                        'tax_amount' => 0,
                        'total' => $lateFeeAmount,
                        'unit' => 'unit',
                    ]);

                    // Update document totals
                    $document->update([
                        'subtotal' => round((float) $document->subtotal + $lateFeeAmount, 2),
                        'total' => $newTotal,
                        'overdue_stage' => 'late_fee_applied',
                    ]);

                    $client->notify(new InvoiceLateFeeNotification($document->fresh(), $tenant, $lateFeeAmount, $newTotal));
                    $lateFees++;
                    $this->info("Late fee applied: {$document->document_number} (+{$lateFeeAmount})");
                }

                // Stage 2: 7+ days overdue — Send reminder
                elseif ($document->overdue_stage === 'late_fee_applied' && $daysOverdue >= 7) {
                    $document->update(['overdue_stage' => 'reminder_7d']);

                    $client->notify(new InvoiceOverdueReminderNotification($document, $tenant, $daysOverdue));
                    $reminders7d++;
                    $this->info("7-day overdue reminder: {$document->document_number}");
                }

                // Stage 3: 14+ days overdue — Termination warning (both email + SMS)
                elseif ($document->overdue_stage === 'reminder_7d' && $daysOverdue >= 14) {
                    $document->update(['overdue_stage' => 'termination_warning']);

                    $client->notify(new InvoiceTerminationWarningNotification($document, $tenant));
                    $terminationWarnings++;
                    $this->info("Termination warning: {$document->document_number}");
                }
            }

            $this->info("Done. Late fees: {$lateFees}, Reminders: {$reminders7d}, Termination warnings: {$terminationWarnings}");

            CronLog::create([
                'tenant_id' => null,
                'command' => $this->signature,
                'description' => "Processed overdue: {$lateFees} late fees, {$reminders7d} reminders, {$terminationWarnings} warnings",
                'results' => [
                    'late_fees_applied' => $lateFees,
                    'overdue_reminders' => $reminders7d,
                    'termination_warnings' => $terminationWarnings,
                ],
                'status' => 'success',
                'started_at' => $startedAt,
                'finished_at' => now(),
            ]);

            return self::SUCCESS;
        } catch (\Throwable $e) {
            CronLog::create([
                'tenant_id' => null,
                'command' => $this->signature,
                'description' => 'Failed to process overdue invoices',
                'status' => 'failed',
                'error' => $e->getMessage(),
                'started_at' => $startedAt,
                'finished_at' => now(),
            ]);

            $this->error($e->getMessage());
            Log::error('ProcessOverdueInvoices failed', ['error' => $e->getMessage()]);
            return self::FAILURE;
        }
    }
}

<?php

namespace App\Console\Commands;

use App\Models\CronLog;
use App\Models\Document;
use App\Models\Followup;
use Carbon\Carbon;
use Illuminate\Console\Command;

class ProcessFollowups extends Command
{
    protected $signature = 'followups:process';

    protected $description = 'Auto-create follow-ups for 3-day overdue invoices, mark broken promises';

    public function handle(): int
    {
        $startedAt = now();
        $today = Carbon::today();

        try {
            $created = 0;
            $broken = 0;

            // 1. Auto-create first follow-up for invoices 3+ days overdue with no existing follow-up
            $overdueInvoices = Document::withoutGlobalScopes()
                ->where('type', 'invoice')
                ->whereNotIn('status', ['paid', 'draft'])
                ->whereDate('due_date', '<=', $today->copy()->subDays(3))
                ->get();

            foreach ($overdueInvoices as $invoice) {
                $hasFollowup = Followup::withoutGlobalScopes()
                    ->where('document_id', $invoice->id)
                    ->exists();

                if (!$hasFollowup) {
                    Followup::withoutGlobalScopes()->create([
                        'tenant_id' => $invoice->tenant_id,
                        'document_id' => $invoice->id,
                        'client_id' => $invoice->client_id,
                        'next_followup' => $today,
                        'notes' => 'Auto-created: invoice is 3+ days overdue with no follow-up.',
                        'status' => 'pending',
                    ]);
                    $created++;
                }
            }

            // 2. Mark broken promises — promised date has passed but invoice still unpaid
            $brokenPromises = Followup::withoutGlobalScopes()
                ->where('status', 'open')
                ->where('outcome', 'promised')
                ->whereNotNull('promise_date')
                ->whereDate('promise_date', '<', $today)
                ->with('document')
                ->get();

            foreach ($brokenPromises as $followup) {
                if ($followup->document && !in_array($followup->document->status, ['paid'])) {
                    $followup->update(['status' => 'broken']);
                    $broken++;

                    // Check call count — if under 3, auto-schedule next follow-up
                    $callCount = Followup::withoutGlobalScopes()
                        ->where('document_id', $followup->document_id)
                        ->whereNotNull('call_date')
                        ->count();

                    if ($callCount < 3) {
                        Followup::withoutGlobalScopes()->create([
                            'tenant_id' => $followup->tenant_id,
                            'document_id' => $followup->document_id,
                            'client_id' => $followup->client_id,
                            'user_id' => $followup->user_id,
                            'next_followup' => $today,
                            'notes' => "Auto-created: client broke promise to pay by {$followup->promise_date->toDateString()}.",
                            'status' => 'broken',
                        ]);
                    }
                }
            }

            // 3. Mark fulfilled — invoice got paid after follow-up
            $fulfilledCount = 0;
            $activeFollowups = Followup::withoutGlobalScopes()
                ->whereIn('status', ['pending', 'open', 'broken'])
                ->with('document')
                ->get();

            foreach ($activeFollowups as $followup) {
                if ($followup->document && $followup->document->status === 'paid') {
                    $followup->update(['status' => 'fulfilled']);
                    $fulfilledCount++;
                }
            }

            $this->info("Created: {$created}, Broken promises: {$broken}, Fulfilled: {$fulfilledCount}");

            CronLog::create([
                'tenant_id' => null,
                'command' => $this->signature,
                'description' => "Created {$created} follow-ups, {$broken} broken promises, {$fulfilledCount} fulfilled",
                'results' => [
                    'followups_created' => $created,
                    'promises_broken' => $broken,
                    'fulfilled' => $fulfilledCount,
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
                'description' => 'Failed to process follow-ups',
                'status' => 'failed',
                'error' => $e->getMessage(),
                'started_at' => $startedAt,
                'finished_at' => now(),
            ]);

            $this->error($e->getMessage());
            return self::FAILURE;
        }
    }
}

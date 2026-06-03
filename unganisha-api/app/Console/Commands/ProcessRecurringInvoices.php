<?php

namespace App\Console\Commands;

use App\Models\CronLog;
use App\Services\RecurringInvoiceService;
use Illuminate\Console\Command;

class ProcessRecurringInvoices extends Command
{
    protected $signature = 'invoices:process-recurring';

    protected $description = 'Auto-create recurring invoices (30 days before due) and send reminders at 21, 14, 7, 3, 1 days';

    public function handle(RecurringInvoiceService $service): int
    {
        $startedAt = now();
        $this->info('Processing recurring invoices...');

        try {
            $result = $service->processAll();

            $this->info("Invoices created: {$result['invoices_created']}");
            $this->info("Reminders sent: {$result['reminders_sent']}");

            $hasFailures = ($result['invoices_failed'] > 0 || $result['reminders_failed'] > 0);
            if ($hasFailures) {
                $this->warn("{$result['invoices_failed']} invoices and {$result['reminders_failed']} reminders FAILED — check logs");
            }

            CronLog::create([
                'tenant_id' => null,
                'command' => $this->signature,
                'description' => "Created {$result['invoices_created']} invoices ({$result['invoices_failed']} failed), sent {$result['reminders_sent']} reminders ({$result['reminders_failed']} failed)",
                'results' => $result,
                // cron_logs.status enum is success|failed — a partially-failed run is
                // flagged 'failed' so it surfaces in the admin log; counts are in the description.
                'status' => $hasFailures ? 'failed' : 'success',
                'started_at' => $startedAt,
                'finished_at' => now(),
            ]);

            return self::SUCCESS;
        } catch (\Throwable $e) {
            CronLog::create([
                'tenant_id' => null,
                'command' => $this->signature,
                'description' => 'Failed to process recurring invoices',
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

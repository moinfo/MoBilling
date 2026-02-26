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

            CronLog::create([
                'tenant_id' => null,
                'command' => $this->signature,
                'description' => "Created {$result['invoices_created']} invoices, sent {$result['reminders_sent']} reminders",
                'results' => $result,
                'status' => 'success',
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

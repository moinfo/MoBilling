<?php

namespace App\Console\Commands;

use App\Services\RecurringInvoiceService;
use Illuminate\Console\Command;

class ProcessRecurringInvoices extends Command
{
    protected $signature = 'invoices:process-recurring';

    protected $description = 'Auto-create recurring invoices (30 days before due) and send reminders at 21, 14, 7, 3, 1 days';

    public function handle(RecurringInvoiceService $service): int
    {
        $this->info('Processing recurring invoices...');

        $result = $service->processAll();

        $this->info("Invoices created: {$result['invoices_created']}");
        $this->info("Reminders sent: {$result['reminders_sent']}");

        return self::SUCCESS;
    }
}

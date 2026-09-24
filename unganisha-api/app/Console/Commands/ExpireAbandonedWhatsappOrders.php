<?php

namespace App\Console\Commands;

use App\Models\Document;
use App\Services\OrderCancellationService;
use Illuminate\Console\Command;

/**
 * Cancel WhatsApp-created orders that were never paid. Conservative on purpose:
 * only invoices carrying the "(WhatsApp order)" marker, only unpaid
 * (sent/overdue, no payment, no completed online payment), only older than N
 * days. Releases the coupon use and cancels the pending domain/subscription
 * through the shared cancel logic. Paid or unmarked documents are never touched.
 */
class ExpireAbandonedWhatsappOrders extends Command
{
    protected $signature = 'whatsapp:expire-abandoned-orders {--days=14} {--dry-run}';
    protected $description = 'Cancel unpaid WhatsApp-created orders older than N days (releases coupons, pending domains/subscriptions)';

    public function handle(OrderCancellationService $svc): int
    {
        $days = max(1, (int) $this->option('days'));
        $dry = (bool) $this->option('dry-run');

        $docs = Document::withoutGlobalScopes()
            ->where('type', 'invoice')
            ->whereIn('status', ['sent', 'overdue'])
            ->where('notes', 'like', '%' . OrderCancellationService::WHATSAPP_MARKER . '%')
            ->where('created_at', '<', now()->subDays($days))
            ->orderBy('created_at')
            ->get();

        $done = 0;
        foreach ($docs as $doc) {
            if (!$svc->cancellable($doc)) {
                continue; // any payment on it: leave alone
            }
            if ($dry) {
                $this->line("[dry-run] would cancel {$doc->document_number} (created {$doc->created_at})");
                $done++;
                continue;
            }
            if ($svc->cancelUnpaidOrder($doc, "Auto-cancelled: unpaid for {$days}+ days")) {
                $this->line("Cancelled {$doc->document_number}");
                $done++;
            }
        }

        $this->info(($dry ? 'Would cancel ' : 'Cancelled ') . $done . ' abandoned WhatsApp order(s).');
        return self::SUCCESS;
    }
}

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Carbon\Carbon;

return new class extends Migration
{
    private const CYCLE_INTERVALS = [
        'monthly' => '1 month',
        'quarterly' => '3 months',
        'half_yearly' => '6 months',
        'yearly' => '1 year',
    ];

    public function up(): void
    {
        // Clear previous incorrect backfill
        DB::table('document_items')
            ->whereNotNull('service_from')
            ->update(['service_from' => null, 'service_to' => null]);

        // Use recurring_invoice_logs to get the correct next_bill_date per product per invoice
        $logs = DB::table('recurring_invoice_logs')
            ->join('product_services', 'product_services.id', '=', 'recurring_invoice_logs.product_service_id')
            ->whereNotNull('recurring_invoice_logs.document_id')
            ->select(
                'recurring_invoice_logs.document_id',
                'recurring_invoice_logs.product_service_id',
                'recurring_invoice_logs.next_bill_date',
                'product_services.billing_cycle'
            )
            ->get();

        foreach ($logs as $log) {
            $interval = self::CYCLE_INTERVALS[$log->billing_cycle] ?? null;
            if (!$interval) {
                continue;
            }

            $nextBill = Carbon::parse($log->next_bill_date);
            $serviceFrom = $nextBill->copy()->sub($interval);
            $serviceTo = $nextBill->copy()->subDay();

            // Update the matching document_item(s)
            DB::table('document_items')
                ->where('document_id', $log->document_id)
                ->where('product_service_id', $log->product_service_id)
                ->whereNull('service_from')
                ->update([
                    'service_from' => $serviceFrom->format('Y-m-d'),
                    'service_to' => $serviceTo->format('Y-m-d'),
                ]);
        }
    }

    public function down(): void
    {
        // No rollback needed
    }
};

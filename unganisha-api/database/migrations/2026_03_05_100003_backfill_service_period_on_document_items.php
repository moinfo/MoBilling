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
        // Backfill service_from/service_to for existing invoice items
        // that link to a product with a billing cycle
        $items = DB::table('document_items')
            ->join('documents', 'documents.id', '=', 'document_items.document_id')
            ->join('product_services', 'product_services.id', '=', 'document_items.product_service_id')
            ->where('documents.type', 'invoice')
            ->whereNotNull('documents.due_date')
            ->whereNotNull('product_services.billing_cycle')
            ->where('product_services.billing_cycle', '!=', 'once')
            ->whereNull('document_items.service_from')
            ->select(
                'document_items.id',
                'documents.due_date',
                'product_services.billing_cycle'
            )
            ->get();

        foreach ($items as $item) {
            $interval = self::CYCLE_INTERVALS[$item->billing_cycle] ?? null;
            if (!$interval) {
                continue;
            }

            $serviceTo = Carbon::parse($item->due_date)->subDay();
            $serviceFrom = $serviceTo->copy()->sub($interval)->addDay();

            DB::table('document_items')
                ->where('id', $item->id)
                ->update([
                    'service_from' => $serviceFrom->format('Y-m-d'),
                    'service_to' => $serviceTo->format('Y-m-d'),
                ]);
        }
    }

    public function down(): void
    {
        // No rollback needed — nullable fields
    }
};

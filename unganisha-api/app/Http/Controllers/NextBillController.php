<?php

namespace App\Http\Controllers;

use App\Models\DocumentItem;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class NextBillController extends Controller
{
    public function index(Request $request)
    {
        $cycleIntervals = [
            'once' => null,
            'monthly' => '1 month',
            'quarterly' => '3 months',
            'half_yearly' => '6 months',
            'yearly' => '1 year',
        ];

        $rows = DocumentItem::query()
            ->join('documents', 'document_items.document_id', '=', 'documents.id')
            ->join('product_services', 'document_items.product_service_id', '=', 'product_services.id')
            ->join('clients', 'documents.client_id', '=', 'clients.id')
            ->where('documents.type', 'invoice')
            ->whereNotNull('product_services.billing_cycle')
            ->where('product_services.billing_cycle', '!=', 'once')
            ->where('product_services.is_active', true)
            ->whereNull('documents.deleted_at')
            ->whereNull('clients.deleted_at')
            ->whereNull('product_services.deleted_at')
            ->where('documents.tenant_id', $request->user()->tenant_id)
            ->select([
                'clients.id as client_id',
                'clients.name as client_name',
                'clients.email as client_email',
                'product_services.id as product_service_id',
                'product_services.name as product_service_name',
                'product_services.billing_cycle',
                'product_services.price',
                DB::raw('MAX(documents.date) as last_billed'),
            ])
            ->groupBy(
                'clients.id', 'clients.name', 'clients.email',
                'product_services.id', 'product_services.name',
                'product_services.billing_cycle', 'product_services.price'
            )
            ->orderBy('clients.name')
            ->get();

        $data = $rows->map(function ($row) use ($cycleIntervals) {
            $interval = $cycleIntervals[$row->billing_cycle] ?? null;
            $lastBilled = \Carbon\Carbon::parse($row->last_billed);
            $nextBill = $interval ? $lastBilled->copy()->add($interval) : null;

            return [
                'client_id' => $row->client_id,
                'client_name' => $row->client_name,
                'client_email' => $row->client_email,
                'product_service_id' => $row->product_service_id,
                'product_service_name' => $row->product_service_name,
                'billing_cycle' => $row->billing_cycle,
                'price' => $row->price,
                'last_billed' => $lastBilled->format('Y-m-d'),
                'next_bill' => $nextBill?->format('Y-m-d'),
                'is_overdue' => $nextBill && $nextBill->isPast(),
            ];
        });

        return response()->json(['data' => $data]);
    }
}

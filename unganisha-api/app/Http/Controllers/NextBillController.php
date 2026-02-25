<?php

namespace App\Http\Controllers;

use App\Models\ClientSubscription;
use App\Models\RecurringInvoiceLog;
use Carbon\Carbon;
use Illuminate\Http\Request;

class NextBillController extends Controller
{
    private const CYCLE_INTERVALS = [
        'monthly' => '1 month',
        'quarterly' => '3 months',
        'half_yearly' => '6 months',
        'yearly' => '1 year',
    ];

    public function index(Request $request)
    {
        $today = Carbon::today();

        $subscriptions = ClientSubscription::query()
            ->where('status', 'active')
            ->with(['client', 'productService'])
            ->whereHas('productService', fn ($q) => $q
                ->where('is_active', true)
                ->whereNotNull('billing_cycle')
                ->where('billing_cycle', '!=', 'once')
            )
            ->get();

        $data = $subscriptions->map(function ($sub) use ($today) {
            $product = $sub->productService;
            $interval = self::CYCLE_INTERVALS[$product->billing_cycle] ?? null;
            if (!$interval) {
                return null;
            }

            $nextBillDate = $this->calculateNextBillDate($sub->start_date, $interval, $today);

            // Find last invoice date from recurring log
            $lastLog = RecurringInvoiceLog::where('client_id', $sub->client_id)
                ->where('product_service_id', $sub->product_service_id)
                ->orderByDesc('invoice_created_at')
                ->first();

            $description = $product->name;
            if ($sub->label) {
                $description .= " — {$sub->label}";
            }

            return [
                'subscription_id' => $sub->id,
                'client_id' => $sub->client_id,
                'client_name' => $sub->client->name,
                'client_email' => $sub->client->email,
                'product_service_id' => $product->id,
                'product_service_name' => $description,
                'billing_cycle' => $product->billing_cycle,
                'price' => $product->price,
                'quantity' => $sub->quantity,
                'last_billed' => $lastLog?->invoice_created_at?->format('Y-m-d'),
                'next_bill' => $nextBillDate?->format('Y-m-d'),
                'is_overdue' => $nextBillDate && $nextBillDate->lt($today),
            ];
        })->filter()->sortBy('next_bill')->values();

        return response()->json(['data' => $data]);
    }

    private function calculateNextBillDate(Carbon $startDate, string $interval, Carbon $today): Carbon
    {
        $date = $startDate->copy();

        while ($date->lt($today)) {
            $date->add($interval);
        }

        return $date;
    }
}
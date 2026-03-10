<?php

namespace App\Http\Controllers\Portal;

use App\Http\Controllers\Controller;
use App\Models\ClientSubscription;
use Carbon\Carbon;
use Illuminate\Http\Request;

class PortalSubscriptionController extends Controller
{
    private const CYCLE_INTERVALS = [
        'monthly' => '1 month',
        'quarterly' => '3 months',
        'half_yearly' => '6 months',
        'yearly' => '1 year',
    ];

    public function index(Request $request)
    {
        $clientId = $request->user()->client_id;

        $subscriptions = ClientSubscription::where('client_id', $clientId)
            ->with('productService:id,name,type,price,billing_cycle')
            ->orderByDesc('start_date')
            ->get()
            ->map(function ($sub) {
                $cycle = $sub->productService?->billing_cycle;
                $sub->billing_cycle = $cycle;
                $sub->next_invoice_date = $this->calculateNextBillDate($sub->start_date, $cycle);
                return $sub;
            });

        return response()->json(['data' => $subscriptions]);
    }

    private function calculateNextBillDate($startDate, ?string $cycle): ?string
    {
        if (!$cycle || $cycle === 'once' || !isset(self::CYCLE_INTERVALS[$cycle])) {
            return null;
        }

        $start = Carbon::parse($startDate);
        $interval = self::CYCLE_INTERVALS[$cycle];
        $today = Carbon::today();
        $next = $start->copy();

        while ($next->lte($today)) {
            $next->add($interval);
        }

        return $next->format('Y-m-d');
    }
}

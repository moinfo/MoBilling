<?php

namespace App\Http\Controllers\Portal;

use App\Http\Controllers\Controller;
use App\Models\ClientSubscription;
use App\Models\Document;
use App\Models\PaymentIn;
use Carbon\Carbon;
use Illuminate\Http\Request;

class PortalDashboardController extends Controller
{
    public function summary(Request $request)
    {
        $clientUser = $request->user();
        $clientId = $clientUser->client_id;

        $invoices = Document::where('client_id', $clientId)
            ->where('type', 'invoice')
            ->whereNotIn('status', ['draft', 'cancelled']);

        $totalInvoiced = (clone $invoices)->sum('total');
        $totalPaid = PaymentIn::whereHas('document', fn ($q) => $q->where('client_id', $clientId))->sum('amount');
        $totalBalance = $totalInvoiced - $totalPaid;

        $overdueCount = (clone $invoices)
            ->where('status', '!=', 'paid')
            ->where('due_date', '<', now())
            ->count();

        $recentInvoices = Document::where('client_id', $clientId)
            ->where('type', 'invoice')
            ->whereNotIn('status', ['draft', 'cancelled'])
            ->orderByDesc('date')
            ->limit(5)
            ->get()
            ->map(fn ($doc) => [
                'id' => $doc->id,
                'document_number' => $doc->document_number,
                'date' => $doc->date->format('Y-m-d'),
                'due_date' => $doc->due_date?->format('Y-m-d'),
                'total' => (float) $doc->total,
                'paid' => (float) $doc->paid_amount,
                'balance' => (float) $doc->balance_due,
                'status' => $doc->status,
            ]);

        $recentPayments = PaymentIn::whereHas('document', fn ($q) => $q->where('client_id', $clientId))
            ->with('document:id,document_number')
            ->orderByDesc('payment_date')
            ->limit(5)
            ->get()
            ->map(fn ($p) => [
                'id' => $p->id,
                'payment_date' => $p->payment_date,
                'amount' => (float) $p->amount,
                'payment_method' => $p->payment_method,
                'reference' => $p->reference,
                'document_number' => $p->document?->document_number,
            ]);

        // Upcoming subscription schedule
        $cycleIntervals = [
            'monthly' => '1 month',
            'quarterly' => '3 months',
            'half_yearly' => '6 months',
            'yearly' => '1 year',
        ];
        $cycleLabels = [
            'once' => 'One-time',
            'monthly' => 'Monthly',
            'quarterly' => 'Quarterly',
            'half_yearly' => 'Half Yearly',
            'yearly' => 'Yearly',
        ];

        $subscriptions = ClientSubscription::where('client_id', $clientId)
            ->where('status', 'active')
            ->with('productService:id,name,price,billing_cycle')
            ->get()
            ->map(function ($sub) use ($cycleIntervals, $cycleLabels) {
                $cycle = $sub->productService?->billing_cycle;
                $nextDate = null;

                if ($cycle && $cycle !== 'once' && isset($cycleIntervals[$cycle])) {
                    $next = Carbon::parse($sub->start_date);
                    $today = Carbon::today();
                    while ($next->lte($today)) {
                        $next->add($cycleIntervals[$cycle]);
                    }
                    $nextDate = $next->format('Y-m-d');
                }

                return [
                    'id' => $sub->id,
                    'service' => $sub->productService?->name,
                    'label' => $sub->label,
                    'price' => (float) ($sub->productService?->price ?? 0),
                    'quantity' => $sub->quantity,
                    'schedule' => $cycleLabels[$cycle] ?? $cycle,
                    'next_invoice_date' => $nextDate,
                ];
            })
            ->sortBy('next_invoice_date')
            ->values();

        return response()->json([
            'total_invoiced' => $totalInvoiced,
            'total_paid' => $totalPaid,
            'total_balance' => $totalBalance,
            'overdue_count' => $overdueCount,
            'recent_invoices' => $recentInvoices,
            'recent_payments' => $recentPayments,
            'upcoming_subscriptions' => $subscriptions,
        ]);
    }
}

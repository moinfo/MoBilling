<?php

namespace App\Http\Controllers;

use App\Models\Bill;
use App\Models\Client;
use App\Models\ClientSubscription;
use App\Models\Document;
use App\Models\Expense;
use App\Models\PaymentIn;
use App\Models\Statutory;
use App\Services\ResellerService;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

class DashboardController extends Controller
{
    public function summary(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;

        // Invoice stats
        $invoices = Document::where('type', 'invoice');
        $totalReceivable = (clone $invoices)->sum('total');
        $totalReceived = PaymentIn::sum('amount');
        $overdueInvoices = (clone $invoices)
            ->where('status', '!=', 'paid')
            ->whereNotNull('due_date')
            ->where('due_date', '<', now())
            ->count();

        // Recent invoices
        $recentInvoices = Document::with('client')
            ->where('type', 'invoice')
            ->orderByDesc('created_at')
            ->limit(5)
            ->get()
            ->map(fn ($doc) => [
                'id' => $doc->id,
                'document_number' => $doc->document_number,
                'client_name' => $doc->client?->name,
                'total' => $doc->total,
                'status' => $doc->status,
                'date' => $doc->date?->format('Y-m-d'),
            ]);

        // Upcoming bills
        $upcomingBills = Bill::where('is_active', true)
            ->where('due_date', '>=', now()->toDateString())
            ->orderBy('due_date')
            ->limit(5)
            ->get()
            ->map(fn ($bill) => [
                'id' => $bill->id,
                'name' => $bill->name,
                'amount' => $bill->amount,
                'due_date' => $bill->due_date?->format('Y-m-d'),
                'category' => $bill->category,
            ]);

        // Overdue bills
        $overdueBills = Bill::where('is_active', true)
            ->where('due_date', '<', now()->toDateString())
            ->count();

        // Counts
        $totalClients = Client::count();
        $totalDocuments = Document::count();

        // SMS balance
        $smsBalance = null;
        $tenant = auth()->user()->tenant;
        if ($tenant && $tenant->sms_enabled && $tenant->sms_authorization) {
            try {
                $reseller = new ResellerService();
                $balanceResult = $reseller->getBalance($tenant);
                $smsBalance = $balanceResult['data']['sms_balance'] ?? $balanceResult['sms_balance'] ?? null;
            } catch (\Throwable $e) {
                Log::warning('Dashboard: failed to fetch SMS balance', ['error' => $e->getMessage()]);
            }
        }

        // --- Chart data ---

        // Monthly revenue (last 6 months): invoiced vs collected
        $sixMonthsAgo = Carbon::now()->subMonths(5)->startOfMonth();
        $monthlyInvoiced = Document::where('type', 'invoice')
            ->where('date', '>=', $sixMonthsAgo)
            ->selectRaw("DATE_FORMAT(date, '%Y-%m') as month, SUM(total) as invoiced")
            ->groupBy('month')
            ->pluck('invoiced', 'month');

        $monthlyCollected = PaymentIn::where('payment_date', '>=', $sixMonthsAgo)
            ->selectRaw("DATE_FORMAT(payment_date, '%Y-%m') as month, SUM(amount) as collected")
            ->groupBy('month')
            ->pluck('collected', 'month');

        $monthlyRevenue = collect();
        for ($i = 5; $i >= 0; $i--) {
            $date = Carbon::now()->subMonths($i);
            $key = $date->format('Y-m');
            $monthlyRevenue->push([
                'month' => $date->format('M'),
                'invoiced' => round((float) ($monthlyInvoiced[$key] ?? 0), 2),
                'collected' => round((float) ($monthlyCollected[$key] ?? 0), 2),
            ]);
        }

        // Invoice status breakdown
        $invoiceStatusBreakdown = Document::where('type', 'invoice')
            ->selectRaw('status, COUNT(*) as count')
            ->groupBy('status')
            ->get()
            ->map(fn ($row) => ['status' => $row->status, 'count' => (int) $row->count]);

        // Payment method breakdown
        $paymentMethodBreakdown = PaymentIn::selectRaw('payment_method, SUM(amount) as amount')
            ->groupBy('payment_method')
            ->get()
            ->map(fn ($row) => [
                'method' => $row->payment_method,
                'amount' => round((float) $row->amount, 2),
            ]);

        // Top 5 clients by invoiced amount
        $topClients = Document::with('client')
            ->where('type', 'invoice')
            ->selectRaw('client_id, SUM(total) as total')
            ->groupBy('client_id')
            ->orderByDesc('total')
            ->limit(5)
            ->get()
            ->map(function ($row) {
                // payments_in links to clients through documents
                $paid = PaymentIn::whereHas('document', fn ($q) => $q->where('client_id', $row->client_id))
                    ->sum('amount');
                return [
                    'name' => $row->client?->name ?? 'Unknown',
                    'total' => round((float) $row->total, 2),
                    'paid' => round((float) $paid, 2),
                ];
            });

        // Subscription stats
        $subscriptionCounts = ClientSubscription::selectRaw('status, COUNT(*) as count')
            ->groupBy('status')
            ->pluck('count', 'status');

        $subscriptionStats = [
            'active' => (int) ($subscriptionCounts['active'] ?? 0),
            'pending' => (int) ($subscriptionCounts['pending'] ?? 0),
            'cancelled' => (int) ($subscriptionCounts['cancelled'] ?? 0),
        ];

        // Upcoming renewals (next 5 subscriptions due based on start_date + billing_cycle)
        $upcomingRenewals = ClientSubscription::with(['client', 'productService'])
            ->where('status', 'active')
            ->get()
            ->map(function ($sub) {
                $cycle = $sub->productService?->billing_cycle;
                $startDate = $sub->start_date;
                if (!$startDate || !$cycle) {
                    return null;
                }

                $nextBill = Carbon::parse($startDate);
                $now = Carbon::now();

                // Advance next_bill_date until it's in the future
                while ($nextBill->lte($now)) {
                    $nextBill = match ($cycle) {
                        'weekly' => $nextBill->addWeek(),
                        'monthly' => $nextBill->addMonth(),
                        'quarterly' => $nextBill->addMonths(3),
                        'semi_annual' => $nextBill->addMonths(6),
                        'annual', 'yearly' => $nextBill->addYear(),
                        default => $nextBill->addMonth(),
                    };
                }

                return [
                    'client_name' => $sub->client?->name ?? 'Unknown',
                    'product_name' => $sub->productService?->name ?? 'Unknown',
                    'label' => $sub->label,
                    'next_bill_date' => $nextBill->format('Y-m-d'),
                    'price' => round((float) ($sub->productService?->price ?? 0), 2),
                ];
            })
            ->filter()
            ->sortBy('next_bill_date')
            ->take(5)
            ->values();

        // Statutory obligations stats
        $activeStatutories = Statutory::where('is_active', true)->get();
        $today = now()->toDateString();

        $statutoryOverdue = $activeStatutories->filter(fn ($s) => $s->next_due_date->lt($today))->count();
        $statutoryDueSoon = $activeStatutories->filter(
            fn ($s) => !$s->next_due_date->lt($today) && $s->next_due_date->diffInDays(now(), false) >= -$s->remind_days_before
        )->count();

        $statutoryStats = [
            'total_active' => $activeStatutories->count(),
            'overdue' => $statutoryOverdue,
            'due_soon' => $statutoryDueSoon,
        ];

        // Overdue / due-soon obligations for dashboard list
        $urgentObligations = $activeStatutories
            ->filter(fn ($s) => $s->next_due_date->lte(now()->addDays($s->remind_days_before)))
            ->sortBy('next_due_date')
            ->take(5)
            ->map(fn ($s) => [
                'id' => $s->id,
                'name' => $s->name,
                'amount' => $s->amount,
                'next_due_date' => $s->next_due_date->format('Y-m-d'),
                'days_remaining' => (int) now()->startOfDay()->diffInDays($s->next_due_date, false),
                'cycle' => $s->cycle,
            ])
            ->values();

        // Total expenses this month
        $totalExpenses = Expense::whereBetween('expense_date', [
            now()->startOfMonth()->toDateString(),
            now()->endOfMonth()->toDateString(),
        ])->sum('amount');

        return response()->json([
            'total_expenses' => round((float) $totalExpenses, 2),
            'total_receivable' => round($totalReceivable, 2),
            'total_received' => round($totalReceived, 2),
            'outstanding' => round($totalReceivable - $totalReceived, 2),
            'overdue_invoices' => $overdueInvoices,
            'overdue_bills' => $overdueBills,
            'total_clients' => $totalClients,
            'total_documents' => $totalDocuments,
            'sms_balance' => $smsBalance,
            'sms_enabled' => $tenant?->sms_enabled ?? false,
            'recent_invoices' => $recentInvoices,
            'upcoming_bills' => $upcomingBills,
            'monthly_revenue' => $monthlyRevenue,
            'invoice_status_breakdown' => $invoiceStatusBreakdown,
            'payment_method_breakdown' => $paymentMethodBreakdown,
            'top_clients' => $topClients,
            'subscription_stats' => $subscriptionStats,
            'upcoming_renewals' => $upcomingRenewals,
            'statutory_stats' => $statutoryStats,
            'urgent_obligations' => $urgentObligations,
        ]);
    }
}

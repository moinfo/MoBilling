<?php

namespace App\Http\Controllers;

use App\Models\Bill;
use App\Models\Client;
use App\Models\ClientSubscription;
use App\Models\CommunicationLog;
use App\Models\Document;
use App\Models\Expense;
use App\Models\Followup;
use App\Models\PaymentIn;
use App\Models\PaymentOut;
use App\Models\Statutory;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ReportController extends Controller
{
    /**
     * Extract validated start/end dates from request, defaulting to current month.
     */
    private function dateRange(Request $request): array
    {
        $start = $request->input('start_date')
            ? Carbon::parse($request->input('start_date'))->startOfDay()
            : now()->startOfMonth()->startOfDay();

        $end = $request->input('end_date')
            ? Carbon::parse($request->input('end_date'))->endOfDay()
            : now()->endOfMonth()->endOfDay();

        return [$start, $end];
    }

    // ─── 1. Revenue Summary ──────────────────────────────────────

    public function revenueSummary(Request $request): JsonResponse
    {
        [$start, $end] = $this->dateRange($request);

        // Monthly invoiced vs collected
        $months = [];
        $cursor = $start->copy()->startOfMonth();
        while ($cursor->lte($end)) {
            $key = $cursor->format('Y-m');
            $monthStart = $cursor->copy()->startOfMonth();
            $monthEnd = $cursor->copy()->endOfMonth();

            $invoiced = Document::where('type', 'invoice')
                ->whereBetween('date', [$monthStart, $monthEnd])
                ->sum('total');

            $collected = PaymentIn::whereBetween('payment_date', [$monthStart, $monthEnd])
                ->sum('amount');

            $months[] = [
                'month' => $cursor->format('M Y'),
                'invoiced' => round((float) $invoiced, 2),
                'collected' => round((float) $collected, 2),
            ];
            $cursor->addMonth();
        }

        $totalInvoiced = collect($months)->sum('invoiced');
        $totalCollected = collect($months)->sum('collected');
        $collectionRate = $totalInvoiced > 0
            ? round(($totalCollected / $totalInvoiced) * 100, 1)
            : 0;

        // Growth: compare with same-length prior period
        $periodDays = $start->diffInDays($end) + 1;
        $priorStart = $start->copy()->subDays($periodDays);
        $priorEnd = $start->copy()->subDay()->endOfDay();

        $priorInvoiced = (float) Document::where('type', 'invoice')
            ->whereBetween('date', [$priorStart, $priorEnd])
            ->sum('total');

        $growth = $priorInvoiced > 0
            ? round((($totalInvoiced - $priorInvoiced) / $priorInvoiced) * 100, 1)
            : null;

        // Supporting data: individual invoices in the period
        $invoices = Document::with('client')
            ->where('type', 'invoice')
            ->whereBetween('date', [$start, $end])
            ->orderByDesc('date')
            ->get()
            ->map(function ($doc) {
                $paid = $doc->payments()->sum('amount');
                return [
                    'id' => $doc->id,
                    'document_number' => $doc->document_number,
                    'client_name' => $doc->client?->name,
                    'date' => $doc->date->format('Y-m-d'),
                    'total' => round((float) $doc->total, 2),
                    'paid' => round((float) $paid, 2),
                    'balance' => round((float) $doc->total - (float) $paid, 2),
                    'status' => $doc->status,
                ];
            });

        return response()->json([
            'months' => $months,
            'total_invoiced' => round($totalInvoiced, 2),
            'total_collected' => round($totalCollected, 2),
            'collection_rate' => $collectionRate,
            'revenue_growth' => $growth,
            'invoices' => $invoices,
        ]);
    }

    // ─── 2. Outstanding & Aging ──────────────────────────────────

    public function outstandingAging(Request $request): JsonResponse
    {
        $invoices = Document::with('client')
            ->where('type', 'invoice')
            ->where('status', '!=', 'paid')
            ->whereNotNull('due_date')
            ->get();

        $bands = ['current' => [], '1_30' => [], '31_60' => [], '61_90' => [], '90_plus' => []];
        $bandTotals = ['current' => 0, '1_30' => 0, '31_60' => 0, '61_90' => 0, '90_plus' => 0];
        $today = now();

        foreach ($invoices as $inv) {
            $paid = $inv->payments()->sum('amount');
            $balance = round((float) $inv->total - (float) $paid, 2);
            if ($balance <= 0) continue;

            $daysOverdue = $today->diffInDays($inv->due_date, false);
            // daysOverdue is negative when past due
            $days = (int) abs(min(0, $daysOverdue));

            $band = match (true) {
                $daysOverdue >= 0 => 'current',
                $days <= 30 => '1_30',
                $days <= 60 => '31_60',
                $days <= 90 => '61_90',
                default => '90_plus',
            };

            $entry = [
                'id' => $inv->id,
                'document_number' => $inv->document_number,
                'client_name' => $inv->client?->name,
                'total' => round((float) $inv->total, 2),
                'paid' => round((float) $paid, 2),
                'balance' => $balance,
                'due_date' => $inv->due_date->format('Y-m-d'),
                'days_overdue' => $days,
            ];

            $bands[$band][] = $entry;
            $bandTotals[$band] += $balance;
        }

        return response()->json([
            'bands' => $bands,
            'band_totals' => array_map(fn ($v) => round($v, 2), $bandTotals),
            'total_outstanding' => round(array_sum($bandTotals), 2),
            'total_invoices' => count($invoices),
        ]);
    }

    // ─── 3. Client Statement ─────────────────────────────────────

    public function clientStatement(Request $request): JsonResponse
    {
        $request->validate(['client_id' => 'required|exists:clients,id']);
        [$start, $end] = $this->dateRange($request);

        $clientId = $request->input('client_id');
        $client = Client::findOrFail($clientId);

        // Invoices (debits)
        $invoices = Document::where('type', 'invoice')
            ->where('client_id', $clientId)
            ->whereBetween('date', [$start, $end])
            ->orderBy('date')
            ->get()
            ->map(fn ($doc) => [
                'date' => $doc->date->format('Y-m-d'),
                'type' => 'invoice',
                'reference' => $doc->document_number,
                'debit' => round((float) $doc->total, 2),
                'credit' => 0,
            ]);

        // Payments (credits)
        $payments = PaymentIn::whereHas('document', fn ($q) => $q->where('client_id', $clientId))
            ->whereBetween('payment_date', [$start, $end])
            ->orderBy('payment_date')
            ->get()
            ->map(fn ($pay) => [
                'date' => $pay->payment_date->format('Y-m-d'),
                'type' => 'payment',
                'reference' => $pay->reference ?? $pay->document?->document_number,
                'debit' => 0,
                'credit' => round((float) $pay->amount, 2),
            ]);

        // Merge and sort by date
        $entries = $invoices->concat($payments)
            ->sortBy('date')
            ->values();

        // Running balance
        $balance = 0;
        $entries = $entries->map(function ($entry) use (&$balance) {
            $balance += $entry['debit'] - $entry['credit'];
            $entry['balance'] = round($balance, 2);
            return $entry;
        });

        $totalDebit = $entries->sum('debit');
        $totalCredit = $entries->sum('credit');

        return response()->json([
            'client' => ['id' => $client->id, 'name' => $client->name, 'email' => $client->email],
            'entries' => $entries,
            'total_debit' => round($totalDebit, 2),
            'total_credit' => round($totalCredit, 2),
            'closing_balance' => round($totalDebit - $totalCredit, 2),
        ]);
    }

    // ─── 4. Payment Collection ───────────────────────────────────

    public function paymentCollection(Request $request): JsonResponse
    {
        [$start, $end] = $this->dateRange($request);

        // Method breakdown
        $byMethod = PaymentIn::whereBetween('payment_date', [$start, $end])
            ->selectRaw("payment_method, COUNT(*) as count, SUM(amount) as total")
            ->groupBy('payment_method')
            ->get()
            ->map(fn ($r) => [
                'method' => $r->payment_method ?? 'Unknown',
                'count' => (int) $r->count,
                'total' => round((float) $r->total, 2),
            ]);

        // Daily collection trend
        $daily = PaymentIn::whereBetween('payment_date', [$start, $end])
            ->selectRaw("DATE(payment_date) as day, SUM(amount) as total, COUNT(*) as count")
            ->groupBy('day')
            ->orderBy('day')
            ->get()
            ->map(fn ($r) => [
                'day' => $r->day,
                'total' => round((float) $r->total, 2),
                'count' => (int) $r->count,
            ]);

        $totalCollected = $byMethod->sum('total');
        $totalTransactions = $byMethod->sum('count');

        // Supporting data: individual payments
        $payments = PaymentIn::with('document.client')
            ->whereBetween('payment_date', [$start, $end])
            ->orderByDesc('payment_date')
            ->get()
            ->map(fn ($p) => [
                'id' => $p->id,
                'payment_date' => $p->payment_date->format('Y-m-d'),
                'amount' => round((float) $p->amount, 2),
                'payment_method' => $p->payment_method,
                'reference' => $p->reference,
                'document_number' => $p->document?->document_number,
                'client_name' => $p->document?->client?->name,
            ]);

        return response()->json([
            'by_method' => $byMethod,
            'daily_trend' => $daily,
            'total_collected' => round($totalCollected, 2),
            'total_transactions' => $totalTransactions,
            'payments' => $payments,
        ]);
    }

    // ─── 5. Expense Report ───────────────────────────────────────

    public function expenseReport(Request $request): JsonResponse
    {
        [$start, $end] = $this->dateRange($request);

        // By sub-category with parent category
        $byCategory = Expense::with('subCategory.category')
            ->whereBetween('expense_date', [$start, $end])
            ->get()
            ->groupBy(fn ($e) => $e->subCategory?->category?->name ?? 'Uncategorized')
            ->map(function ($items, $category) {
                $subGroups = $items->groupBy(fn ($e) => $e->subCategory?->name ?? 'Other');
                return [
                    'category' => $category,
                    'total' => round($items->sum('amount'), 2),
                    'sub_categories' => $subGroups->map(fn ($sub, $name) => [
                        'name' => $name,
                        'total' => round($sub->sum('amount'), 2),
                        'count' => $sub->count(),
                    ])->values(),
                ];
            })->values();

        // Monthly trend
        $monthly = Expense::whereBetween('expense_date', [$start, $end])
            ->selectRaw("DATE_FORMAT(expense_date, '%Y-%m') as month, SUM(amount) as total")
            ->groupBy('month')
            ->orderBy('month')
            ->get()
            ->map(fn ($r) => [
                'month' => Carbon::parse($r->month . '-01')->format('M Y'),
                'total' => round((float) $r->total, 2),
            ]);

        $totalExpenses = $byCategory->sum('total');

        // Supporting data: individual expenses
        $expenses = Expense::with('subCategory.category')
            ->whereBetween('expense_date', [$start, $end])
            ->orderByDesc('expense_date')
            ->get()
            ->map(fn ($e) => [
                'id' => $e->id,
                'expense_date' => $e->expense_date->format('Y-m-d'),
                'description' => $e->description,
                'amount' => round((float) $e->amount, 2),
                'category' => $e->subCategory?->category?->name,
                'sub_category' => $e->subCategory?->name,
                'payment_method' => $e->payment_method,
                'reference' => $e->reference,
            ]);

        return response()->json([
            'by_category' => $byCategory,
            'monthly_trend' => $monthly,
            'total_expenses' => round($totalExpenses, 2),
            'expenses' => $expenses,
        ]);
    }

    // ─── 6. Profit & Loss ────────────────────────────────────────

    public function profitLoss(Request $request): JsonResponse
    {
        [$start, $end] = $this->dateRange($request);

        // Revenue = payments received
        $revenue = round((float) PaymentIn::whereBetween('payment_date', [$start, $end])->sum('amount'), 2);

        // Cost of bills / statutory
        $billPayments = round((float) PaymentOut::whereBetween('payment_date', [$start, $end])->sum('amount'), 2);

        // Expenses
        $expenses = round((float) Expense::whereBetween('expense_date', [$start, $end])->sum('amount'), 2);

        $totalCosts = round($billPayments + $expenses, 2);
        $netProfit = round($revenue - $totalCosts, 2);
        $margin = $revenue > 0 ? round(($netProfit / $revenue) * 100, 1) : 0;

        // Monthly breakdown
        $months = [];
        $cursor = $start->copy()->startOfMonth();
        while ($cursor->lte($end)) {
            $mStart = $cursor->copy()->startOfMonth();
            $mEnd = $cursor->copy()->endOfMonth();

            $mRevenue = round((float) PaymentIn::whereBetween('payment_date', [$mStart, $mEnd])->sum('amount'), 2);
            $mBills = round((float) PaymentOut::whereBetween('payment_date', [$mStart, $mEnd])->sum('amount'), 2);
            $mExpenses = round((float) Expense::whereBetween('expense_date', [$mStart, $mEnd])->sum('amount'), 2);

            $months[] = [
                'month' => $cursor->format('M Y'),
                'revenue' => $mRevenue,
                'bill_payments' => $mBills,
                'expenses' => $mExpenses,
                'net_profit' => round($mRevenue - $mBills - $mExpenses, 2),
            ];
            $cursor->addMonth();
        }

        // Supporting data: revenue entries (payments received)
        $revenueEntries = PaymentIn::with('document.client')
            ->whereBetween('payment_date', [$start, $end])
            ->orderByDesc('payment_date')
            ->get()
            ->map(fn ($p) => [
                'date' => $p->payment_date->format('Y-m-d'),
                'type' => 'revenue',
                'description' => 'Payment: ' . ($p->document?->document_number ?? $p->reference ?? '-'),
                'client' => $p->document?->client?->name,
                'amount' => round((float) $p->amount, 2),
            ]);

        // Bill payments
        $billEntries = PaymentOut::with('bill')
            ->whereBetween('payment_date', [$start, $end])
            ->orderByDesc('payment_date')
            ->get()
            ->map(fn ($p) => [
                'date' => $p->payment_date->format('Y-m-d'),
                'type' => 'bill_payment',
                'description' => 'Bill: ' . ($p->bill?->name ?? '-'),
                'client' => null,
                'amount' => round((float) $p->amount, 2),
            ]);

        // Expense entries
        $expenseEntries = Expense::with('subCategory.category')
            ->whereBetween('expense_date', [$start, $end])
            ->orderByDesc('expense_date')
            ->get()
            ->map(fn ($e) => [
                'date' => $e->expense_date->format('Y-m-d'),
                'type' => 'expense',
                'description' => $e->description ?: ($e->subCategory?->name ?? 'Expense'),
                'client' => null,
                'amount' => round((float) $e->amount, 2),
            ]);

        $entries = $revenueEntries->concat($billEntries)->concat($expenseEntries)
            ->sortByDesc('date')
            ->values();

        return response()->json([
            'revenue' => $revenue,
            'bill_payments' => $billPayments,
            'expenses' => $expenses,
            'total_costs' => $totalCosts,
            'net_profit' => $netProfit,
            'profit_margin' => $margin,
            'months' => $months,
            'entries' => $entries,
        ]);
    }

    // ─── 7. Statutory Compliance ─────────────────────────────────

    public function statutoryCompliance(Request $request): JsonResponse
    {
        $obligations = Statutory::with('billCategory')->where('is_active', true)->get();
        $today = now();

        $items = $obligations->map(function ($s) use ($today) {
            $daysUntilDue = (int) $today->startOfDay()->diffInDays($s->next_due_date, false);

            // Count bills paid on time vs late
            $bills = Bill::where('statutory_id', $s->id)->get();
            $paidOnTime = $bills->filter(fn ($b) => $b->paid_at && Carbon::parse($b->paid_at)->lte($b->due_date))->count();
            $paidLate = $bills->filter(fn ($b) => $b->paid_at && Carbon::parse($b->paid_at)->gt($b->due_date))->count();
            $unpaid = $bills->filter(fn ($b) => !$b->paid_at)->count();

            $status = match (true) {
                $daysUntilDue < 0 => 'overdue',
                $daysUntilDue <= $s->remind_days_before => 'due_soon',
                default => 'on_track',
            };

            return [
                'id' => $s->id,
                'name' => $s->name,
                'category' => $s->billCategory?->name,
                'cycle' => $s->cycle,
                'amount' => round((float) $s->amount, 2),
                'next_due_date' => $s->next_due_date->format('Y-m-d'),
                'days_until_due' => $daysUntilDue,
                'status' => $status,
                'paid_on_time' => $paidOnTime,
                'paid_late' => $paidLate,
                'unpaid' => $unpaid,
            ];
        });

        $summary = [
            'total_active' => $items->count(),
            'overdue' => $items->where('status', 'overdue')->count(),
            'due_soon' => $items->where('status', 'due_soon')->count(),
            'on_track' => $items->where('status', 'on_track')->count(),
            'compliance_rate' => $items->count() > 0
                ? round(($items->where('status', '!=', 'overdue')->count() / $items->count()) * 100, 1)
                : 100,
        ];

        return response()->json([
            'summary' => $summary,
            'obligations' => $items->sortBy('days_until_due')->values(),
        ]);
    }

    // ─── 8. Subscription Report ──────────────────────────────────

    public function subscriptionReport(Request $request): JsonResponse
    {
        $subscriptions = ClientSubscription::with(['client', 'productService'])->get();

        $byStatus = $subscriptions->groupBy('status')->map(fn ($g) => $g->count());

        $activeRevenue = $subscriptions->where('status', 'active')->sum(function ($sub) {
            $price = (float) ($sub->productService?->price ?? 0);
            $qty = (int) ($sub->quantity ?? 1);
            return $price * $qty;
        });

        // Upcoming renewals (next 30 days)
        $renewals = $subscriptions->where('status', 'active')
            ->map(function ($sub) {
                $cycle = $sub->productService?->billing_cycle;
                $startDate = $sub->start_date;
                if (!$startDate || !$cycle) return null;

                $nextBill = Carbon::parse($startDate);
                $now = Carbon::now();
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
                    'client_name' => $sub->client?->name,
                    'product_name' => $sub->productService?->name,
                    'label' => $sub->label,
                    'next_bill_date' => $nextBill->format('Y-m-d'),
                    'price' => round((float) ($sub->productService?->price ?? 0) * ($sub->quantity ?? 1), 2),
                    'days_until' => (int) $now->diffInDays($nextBill, false),
                ];
            })
            ->filter()
            ->sortBy('next_bill_date')
            ->values();

        // Monthly forecast (sum of active subscription values)
        $monthlyForecast = round($activeRevenue, 2);

        return response()->json([
            'by_status' => [
                'active' => (int) ($byStatus['active'] ?? 0),
                'pending' => (int) ($byStatus['pending'] ?? 0),
                'cancelled' => (int) ($byStatus['cancelled'] ?? 0),
            ],
            'total_subscriptions' => $subscriptions->count(),
            'active_monthly_revenue' => round($activeRevenue, 2),
            'monthly_forecast' => $monthlyForecast,
            'upcoming_renewals' => $renewals,
        ]);
    }

    // ─── 9. Collection Effectiveness ─────────────────────────────

    public function collectionEffectiveness(Request $request): JsonResponse
    {
        [$start, $end] = $this->dateRange($request);

        $followups = Followup::whereBetween('call_date', [$start, $end])->get();

        $totalFollowups = $followups->count();

        // Outcome breakdown
        $byOutcome = $followups->groupBy('outcome')->map(fn ($g) => $g->count());

        // Promise fulfillment: followups with outcome=promised that have payments near promise_date
        $promises = $followups->where('outcome', 'promised')->filter(fn ($f) => $f->promise_date);
        $fulfilled = 0;

        foreach ($promises as $f) {
            $hasPay = PaymentIn::whereHas('document', fn ($q) => $q->where('client_id', $f->client_id))
                ->whereBetween('payment_date', [
                    $f->promise_date->copy()->subDays(3),
                    $f->promise_date->copy()->addDays(7),
                ])
                ->exists();
            if ($hasPay) $fulfilled++;
        }

        $promiseCount = $promises->count();
        $fulfillmentRate = $promiseCount > 0
            ? round(($fulfilled / $promiseCount) * 100, 1)
            : 0;

        // Monthly trend
        $monthly = $followups->groupBy(fn ($f) => $f->call_date->format('Y-m'))
            ->sortKeys()
            ->map(function ($group, $month) {
                return [
                    'month' => Carbon::parse($month . '-01')->format('M Y'),
                    'total' => $group->count(),
                    'promised' => $group->where('outcome', 'promised')->count(),
                    'paid' => $group->where('outcome', 'paid')->count(),
                    'no_answer' => $group->where('outcome', 'no_answer')->count(),
                ];
            })->values();

        // Supporting data: individual follow-ups
        $followupList = Followup::with(['client', 'document', 'user'])
            ->whereBetween('call_date', [$start, $end])
            ->orderByDesc('call_date')
            ->get()
            ->map(fn ($f) => [
                'id' => $f->id,
                'call_date' => $f->call_date->format('Y-m-d'),
                'client_name' => $f->client?->name,
                'document_number' => $f->document?->document_number,
                'outcome' => $f->outcome,
                'notes' => $f->notes,
                'promise_date' => $f->promise_date?->format('Y-m-d'),
                'promise_amount' => $f->promise_amount ? round((float) $f->promise_amount, 2) : null,
                'agent' => $f->user?->name,
                'status' => $f->status,
            ]);

        return response()->json([
            'total_followups' => $totalFollowups,
            'by_outcome' => $byOutcome,
            'promise_count' => $promiseCount,
            'promises_fulfilled' => $fulfilled,
            'fulfillment_rate' => $fulfillmentRate,
            'monthly_trend' => $monthly,
            'followups' => $followupList,
        ]);
    }

    // ─── 10. Communication Log ───────────────────────────────────

    public function communicationLog(Request $request): JsonResponse
    {
        [$start, $end] = $this->dateRange($request);

        $logs = CommunicationLog::whereBetween('created_at', [$start, $end])->get();

        // By channel
        $byChannel = $logs->groupBy('channel')->map(function ($group, $channel) {
            $sent = $group->where('status', 'sent')->count();
            $failed = $group->where('status', 'failed')->count();
            $total = $group->count();
            return [
                'channel' => $channel,
                'total' => $total,
                'sent' => $sent,
                'failed' => $failed,
                'delivery_rate' => $total > 0 ? round(($sent / $total) * 100, 1) : 0,
            ];
        })->values();

        // By type
        $byType = $logs->groupBy('type')->map(function ($group, $type) {
            return [
                'type' => $type,
                'total' => $group->count(),
                'sent' => $group->where('status', 'sent')->count(),
                'failed' => $group->where('status', 'failed')->count(),
            ];
        })->values();

        // Daily volume
        $daily = $logs->groupBy(fn ($l) => $l->created_at->format('Y-m-d'))
            ->sortKeys()
            ->map(fn ($group, $day) => [
                'day' => $day,
                'total' => $group->count(),
                'sent' => $group->where('status', 'sent')->count(),
                'failed' => $group->where('status', 'failed')->count(),
            ])->values();

        $totalSent = $logs->where('status', 'sent')->count();
        $totalFailed = $logs->where('status', 'failed')->count();
        $total = $logs->count();

        // Supporting data: individual messages
        $messages = CommunicationLog::with('client')
            ->whereBetween('created_at', [$start, $end])
            ->orderByDesc('created_at')
            ->limit(200)
            ->get()
            ->map(fn ($l) => [
                'id' => $l->id,
                'created_at' => $l->created_at->format('Y-m-d H:i'),
                'channel' => $l->channel,
                'type' => $l->type,
                'recipient' => $l->recipient,
                'client_name' => $l->client?->name,
                'subject' => $l->subject,
                'status' => $l->status,
                'error' => $l->error,
            ]);

        return response()->json([
            'by_channel' => $byChannel,
            'by_type' => $byType,
            'daily_volume' => $daily,
            'total' => $total,
            'total_sent' => $totalSent,
            'total_failed' => $totalFailed,
            'overall_delivery_rate' => $total > 0 ? round(($totalSent / $total) * 100, 1) : 0,
            'messages' => $messages,
        ]);
    }
}

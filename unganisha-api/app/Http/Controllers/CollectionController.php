<?php

namespace App\Http\Controllers;

use App\Models\Document;
use App\Models\Followup;
use App\Models\PaymentIn;
use Carbon\Carbon;
use Illuminate\Http\Request;

class CollectionController extends Controller
{
    public function dashboard(Request $request)
    {
        $today = Carbon::today();
        $monthStart = $today->copy()->startOfMonth();
        $monthEnd = $today->copy()->endOfMonth();

        // --- Today's due invoices (unpaid with due_date = today) ---
        $todayDue = Document::with('client')
            ->where('type', 'invoice')
            ->whereDate('due_date', $today)
            ->whereNotIn('status', ['paid', 'draft', 'cancelled'])
            ->get()
            ->map(fn ($d) => [
                'id' => $d->id,
                'document_number' => $d->document_number,
                'client_name' => $d->client?->name,
                'client_id' => $d->client_id,
                'total' => (float) $d->total,
                'paid_amount' => (float) $d->paid_amount,
                'balance_due' => (float) $d->balance_due,
                'status' => $d->status,
            ]);

        // --- Overdue invoices (due_date < today, still unpaid) ---
        $overdue = Document::with('client')
            ->where('type', 'invoice')
            ->whereDate('due_date', '<', $today)
            ->whereNotIn('status', ['paid', 'draft', 'cancelled'])
            ->orderBy('due_date')
            ->get()
            ->map(fn ($d) => [
                'id' => $d->id,
                'document_number' => $d->document_number,
                'client_name' => $d->client?->name,
                'client_id' => $d->client_id,
                'total' => (float) $d->total,
                'paid_amount' => (float) $d->paid_amount,
                'balance_due' => (float) $d->balance_due,
                'due_date' => $d->due_date?->toDateString(),
                'days_overdue' => (int) $today->diffInDays($d->due_date),
                'status' => $d->status,
            ]);

        // --- Upcoming due (next 30 days, excluding today) ---
        $upcoming = Document::with('client')
            ->where('type', 'invoice')
            ->whereDate('due_date', '>', $today)
            ->whereDate('due_date', '<=', $today->copy()->addDays(30))
            ->whereNotIn('status', ['paid', 'draft', 'cancelled'])
            ->orderBy('due_date')
            ->get()
            ->map(fn ($d) => [
                'id' => $d->id,
                'document_number' => $d->document_number,
                'client_name' => $d->client?->name,
                'client_id' => $d->client_id,
                'total' => (float) $d->total,
                'paid_amount' => (float) $d->paid_amount,
                'balance_due' => (float) $d->balance_due,
                'due_date' => $d->due_date?->toDateString(),
                'days_until_due' => (int) $today->diffInDays($d->due_date),
                'status' => $d->status,
            ]);

        // --- Today's payments ---
        $todayPayments = PaymentIn::with('document.client')
            ->whereDate('payment_date', $today)
            ->orderByDesc('created_at')
            ->get()
            ->map(fn ($p) => [
                'id' => $p->id,
                'amount' => (float) $p->amount,
                'payment_method' => $p->payment_method,
                'reference' => $p->reference,
                'document_number' => $p->document?->document_number,
                'client_name' => $p->document?->client?->name,
            ]);

        // --- Summary calculations ---
        $todayDueTotal = Document::where('type', 'invoice')
            ->whereDate('due_date', $today)
            ->whereNotIn('status', ['paid', 'draft', 'cancelled'])
            ->sum('total');

        $todayDuePaid = PaymentIn::whereHas('document', fn ($q) => $q
            ->where('type', 'invoice')
            ->whereDate('due_date', $today)
        )->sum('amount');

        $todayCollected = PaymentIn::whereDate('payment_date', $today)->sum('amount');

        $overdueTotal = Document::where('type', 'invoice')
            ->whereDate('due_date', '<', $today)
            ->whereNotIn('status', ['paid', 'draft', 'cancelled'])
            ->sum('total');

        $overduePaid = (float) $overdue->sum('paid_amount');

        // Month target = overdue carry-over + due this month (what you should collect this month)
        $monthDue = (float) Document::where('type', 'invoice')
            ->whereDate('due_date', '>=', $monthStart)
            ->whereDate('due_date', '<=', $monthEnd)
            ->whereNotIn('status', ['draft', 'cancelled'])
            ->sum('total');

        $overdueCarryOver = (float) Document::where('type', 'invoice')
            ->whereDate('due_date', '<', $monthStart)
            ->whereNotIn('status', ['paid', 'draft', 'cancelled'])
            ->get()
            ->sum(fn ($d) => $d->balance_due);

        $monthTarget = $monthDue + $overdueCarryOver;

        $monthCollected = PaymentIn::whereDate('payment_date', '>=', $monthStart)
            ->whereDate('payment_date', '<=', $monthEnd)
            ->sum('amount');

        // --- Total outstanding (all unpaid invoices) ---
        $allUnpaid = Document::where('type', 'invoice')
            ->whereNotIn('status', ['paid', 'draft', 'cancelled'])
            ->get();

        $totalOutstanding = (float) $allUnpaid->sum('balance_due');
        $totalInvoiced = (float) $allUnpaid->sum('total');
        $totalPartialPaid = (float) $allUnpaid->sum('paid_amount');
        $unpaidCount = $allUnpaid->count();

        // --- Aging breakdown ---
        $aging = [
            'current' => 0,     // not yet due
            '1_30' => 0,        // 1-30 days overdue
            '31_60' => 0,       // 31-60 days overdue
            '61_90' => 0,       // 61-90 days overdue
            'over_90' => 0,     // 90+ days overdue
        ];

        foreach ($allUnpaid as $doc) {
            $balance = (float) $doc->balance_due;
            if (!$doc->due_date || $doc->due_date->gte($today)) {
                $aging['current'] += $balance;
            } else {
                $daysOverdue = (int) $today->diffInDays($doc->due_date);
                if ($daysOverdue <= 30) {
                    $aging['1_30'] += $balance;
                } elseif ($daysOverdue <= 60) {
                    $aging['31_60'] += $balance;
                } elseif ($daysOverdue <= 90) {
                    $aging['61_90'] += $balance;
                } else {
                    $aging['over_90'] += $balance;
                }
            }
        }

        // --- Call plan: scheduled call dates for the month ---
        $callPlan = $this->buildCallPlan($allUnpaid, $monthStart, $monthEnd, $today);

        return response()->json([
            'data' => [
                'summary' => [
                    'total_outstanding' => $totalOutstanding,
                    'total_invoiced' => $totalInvoiced,
                    'total_partial_paid' => $totalPartialPaid,
                    'unpaid_count' => $unpaidCount,
                    'today_due' => (float) $todayDueTotal,
                    'today_due_paid' => (float) $todayDuePaid,
                    'today_collected' => (float) $todayCollected,
                    'today_balance' => (float) ($todayDueTotal - $todayDuePaid),
                    'overdue_total' => (float) $overdueTotal,
                    'overdue_paid' => (float) $overduePaid,
                    'overdue_balance' => (float) ($overdueTotal - $overduePaid),
                    'month_target' => (float) $monthTarget,
                    'month_collected' => (float) $monthCollected,
                    'month_balance' => (float) ($monthTarget - $monthCollected),
                ],
                'aging' => $aging,
                'today_due' => $todayDue->values(),
                'today_payments' => $todayPayments->values(),
                'overdue' => $overdue->values(),
                'upcoming' => $upcoming->values(),
                'call_plan' => $callPlan,
            ],
        ]);
    }

    /**
     * Build a call plan calendar for the month.
     *
     * Schedule logic per unpaid invoice:
     * - If due date is in the future: call at 7d, 3d, 1d before due
     * - On due date itself
     * - If overdue: call immediately (today), then every 5 days
     * - Existing followups override auto-schedule for that invoice
     */
    private function buildCallPlan($unpaidInvoices, Carbon $monthStart, Carbon $monthEnd, Carbon $today): array
    {
        // Pre-defined call schedule relative to due date (negative = before, 0 = on due, positive = after)
        $predueDays = [-7, -3, -1, 0];
        $overdueInterval = 5; // call every 5 days after due

        // Load existing active followups for these invoices
        $invoiceIds = $unpaidInvoices->pluck('id')->toArray();
        $existingFollowups = Followup::whereIn('document_id', $invoiceIds)
            ->whereIn('status', ['pending', 'open'])
            ->whereNotNull('next_followup')
            ->get()
            ->groupBy('document_id');

        $calendar = []; // date => [entries]

        foreach ($unpaidInvoices as $doc) {
            $dueDate = $doc->due_date;
            if (!$dueDate) continue;

            $clientName = $doc->client?->name ?? 'Unknown';
            $clientPhone = $doc->client?->phone;
            $balance = (float) $doc->balance_due;

            // Check if this invoice has existing followups scheduled
            $hasFollowup = isset($existingFollowups[$doc->id]);
            $followupDates = $hasFollowup
                ? $existingFollowups[$doc->id]->pluck('next_followup')->map(fn ($d) => $d->format('Y-m-d'))->toArray()
                : [];

            $scheduledDates = [];

            if ($dueDate->gte($today)) {
                // Future due: schedule pre-due calls
                foreach ($predueDays as $offset) {
                    $callDate = $dueDate->copy()->addDays($offset);
                    if ($callDate->gte($today) && $callDate->gte($monthStart) && $callDate->lte($monthEnd)) {
                        $scheduledDates[] = [
                            'date' => $callDate->format('Y-m-d'),
                            'type' => $offset === 0 ? 'due_date' : 'reminder',
                            'label' => $offset === 0 ? 'Due date' : abs($offset) . 'd before due',
                        ];
                    }
                }
            } else {
                // Overdue: call today, then every N days
                $startCall = $today->copy();
                for ($i = 0; $i < 6; $i++) {
                    $callDate = $startCall->copy()->addDays($i * $overdueInterval);
                    if ($callDate->gt($monthEnd)) break;
                    if ($callDate->gte($monthStart)) {
                        $scheduledDates[] = [
                            'date' => $callDate->format('Y-m-d'),
                            'type' => $i === 0 ? 'overdue_urgent' : 'overdue_followup',
                            'label' => $i === 0 ? 'Overdue — call now' : 'Overdue follow-up',
                        ];
                    }
                }
            }

            // Add existing followup dates that aren't already in the schedule
            foreach ($followupDates as $fDate) {
                $fCarbon = Carbon::parse($fDate);
                if ($fCarbon->gte($monthStart) && $fCarbon->lte($monthEnd)) {
                    $alreadyScheduled = collect($scheduledDates)->contains('date', $fDate);
                    if (!$alreadyScheduled) {
                        $scheduledDates[] = [
                            'date' => $fDate,
                            'type' => 'followup',
                            'label' => 'Scheduled follow-up',
                        ];
                    }
                }
            }

            // Add to calendar
            foreach ($scheduledDates as $entry) {
                $date = $entry['date'];
                $calendar[$date][] = [
                    'document_id' => $doc->id,
                    'document_number' => $doc->document_number,
                    'client_name' => $clientName,
                    'client_phone' => $clientPhone,
                    'balance' => $balance,
                    'due_date' => $dueDate->format('Y-m-d'),
                    'type' => $entry['type'],
                    'label' => $entry['label'],
                    'has_followup' => in_array($date, $followupDates),
                ];
            }
        }

        // Sort by date
        ksort($calendar);

        return $calendar;
    }
}

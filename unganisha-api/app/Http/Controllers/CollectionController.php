<?php

namespace App\Http\Controllers;

use App\Models\Document;
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
            ->whereNotIn('status', ['paid', 'draft'])
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
            ->whereNotIn('status', ['paid', 'draft'])
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
            ->whereNotIn('status', ['paid', 'draft'])
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
            ->whereNotIn('status', ['paid', 'draft'])
            ->sum('total');

        $todayDuePaid = PaymentIn::whereHas('document', fn ($q) => $q
            ->where('type', 'invoice')
            ->whereDate('due_date', $today)
        )->sum('amount');

        $todayCollected = PaymentIn::whereDate('payment_date', $today)->sum('amount');

        $overdueTotal = Document::where('type', 'invoice')
            ->whereDate('due_date', '<', $today)
            ->whereNotIn('status', ['paid', 'draft'])
            ->sum('total');

        $overduePaid = (float) $overdue->sum('paid_amount');

        $monthTarget = Document::where('type', 'invoice')
            ->whereDate('due_date', '>=', $monthStart)
            ->whereDate('due_date', '<=', $monthEnd)
            ->whereNotIn('status', ['draft'])
            ->sum('total');

        $monthCollected = PaymentIn::whereDate('payment_date', '>=', $monthStart)
            ->whereDate('payment_date', '<=', $monthEnd)
            ->sum('amount');

        return response()->json([
            'data' => [
                'summary' => [
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
                'today_due' => $todayDue->values(),
                'today_payments' => $todayPayments->values(),
                'overdue' => $overdue->values(),
                'upcoming' => $upcoming->values(),
            ],
        ]);
    }
}

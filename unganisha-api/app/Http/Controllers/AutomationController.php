<?php

namespace App\Http\Controllers;

use App\Models\CommunicationLog;
use App\Models\CronLog;
use App\Services\ReminderForecastService;
use Carbon\Carbon;
use Illuminate\Http\Request;

class AutomationController extends Controller
{
    /** Read-only projection of what the reminder crons will send over the next N days. */
    public function upcomingReminders(Request $request, ReminderForecastService $forecast)
    {
        $days = max(1, min(60, (int) $request->get('days', 14)));

        return response()->json([
            'data' => $forecast->forecast(auth()->user()->tenant_id, $days),
        ]);
    }

    /** Export the upcoming-reminders forecast as PDF or CSV (Excel-friendly) — one row per client per event. */
    public function exportUpcomingReminders(Request $request, ReminderForecastService $forecast)
    {
        $data = $request->validate([
            'days' => 'nullable|integer|min:1|max:60',
            'format' => 'required|in:pdf,csv',
        ]);
        $days = (int) ($data['days'] ?? 14);
        $tenant = auth()->user()->tenant;

        $events = $forecast->forecast($tenant->id, $days);
        $generatedAt = now();

        if ($data['format'] === 'pdf') {
            $pdf = \Barryvdh\DomPDF\Facade\Pdf::loadView('pdf.upcoming-reminders', [
                'events' => $events,
                'tenant' => $tenant,
                'days' => $days,
                'generatedAt' => $generatedAt,
            ]);

            return $pdf->download("upcoming-reminders-{$days}d.pdf");
        }

        $rows = [['Date', 'Client', 'Type', 'Detail', 'Channels', 'Email', 'Phone']];
        foreach ($events as $e) {
            $rows[] = [
                $e['date'], $e['client_name'], $e['category'], $e['label'],
                implode('/', $e['channels']), $e['recipient_email'] ?? '', $e['recipient_phone'] ?? '',
            ];
        }

        $csv = fopen('php://temp', 'r+');
        fwrite($csv, "\xEF\xBB\xBF");   // BOM so Excel reads UTF-8
        foreach ($rows as $r) {
            fputcsv($csv, $r);
        }
        rewind($csv);

        return response(stream_get_contents($csv), 200, [
            'Content-Type' => 'text/csv; charset=UTF-8',
            'Content-Disposition' => "attachment; filename=upcoming-reminders-{$days}d.csv",
        ]);
    }

    public function summary(Request $request)
    {
        $date = $request->get('date', today()->toDateString());
        $start = Carbon::parse($date)->startOfDay();
        $end = Carbon::parse($date)->endOfDay();

        // Aggregate cron results for the day
        $cronLogs = CronLog::whereBetween('created_at', [$start, $end])
            ->where('status', 'success')
            ->get();

        $invoicesCreated = 0;
        $remindersSent = 0;
        $billsGenerated = 0;
        $subscriptionsExpired = 0;

        foreach ($cronLogs as $log) {
            $results = $log->results ?? [];
            $invoicesCreated += $results['invoices_created'] ?? 0;
            $remindersSent += ($results['reminders_sent'] ?? 0)
                + ($results['upcoming_reminders'] ?? 0)
                + ($results['overdue_reminders'] ?? 0);
            $billsGenerated += $results['bills_generated'] ?? 0;
            $subscriptionsExpired += $results['subscriptions_expired'] ?? 0;
        }

        // Communication counts
        $emailsSent = CommunicationLog::where('channel', 'email')
            ->whereBetween('created_at', [$start, $end])
            ->count();

        $smsSent = CommunicationLog::where('channel', 'sms')
            ->whereBetween('created_at', [$start, $end])
            ->count();

        $failedComms = CommunicationLog::where('status', 'failed')
            ->whereBetween('created_at', [$start, $end])
            ->count();

        return response()->json([
            'data' => [
                'date' => $date,
                'invoices_created' => $invoicesCreated,
                'reminders_sent' => $remindersSent,
                'bills_generated' => $billsGenerated,
                'subscriptions_expired' => $subscriptionsExpired,
                'emails_sent' => $emailsSent,
                'sms_sent' => $smsSent,
                'failed_communications' => $failedComms,
            ],
        ]);
    }

    public function cronLogs(Request $request)
    {
        $query = CronLog::query()->orderByDesc('created_at');

        if ($request->has('date')) {
            $date = Carbon::parse($request->date);
            $query->whereBetween('created_at', [$date->startOfDay(), $date->copy()->endOfDay()]);
        }

        return response()->json($query->paginate($request->per_page ?? 20));
    }

    public function communicationLogs(Request $request)
    {
        $query = CommunicationLog::with('client:id,name')->orderByDesc('created_at');

        // A search overrides the date filter — staff looking up what a
        // specific client received need every historical message, not just
        // today's, and typing a search term makes that intent explicit.
        if ($request->filled('search')) {
            $search = $request->search;
            $query->where(fn ($q) => $q
                ->where('recipient', 'like', "%{$search}%")
                ->orWhereHas('client', fn ($c) => $c->where('name', 'like', "%{$search}%")));
        } elseif ($request->has('date')) {
            $date = Carbon::parse($request->date);
            $query->whereBetween('created_at', [$date->startOfDay(), $date->copy()->endOfDay()]);
        }

        if ($request->boolean('client_only')) {
            $query->whereNotNull('client_id');
        }

        if ($request->has('channel')) {
            $query->where('channel', $request->channel);
        }

        if ($request->has('type')) {
            $query->where('type', $request->type);
        }

        if ($request->has('status')) {
            $query->where('status', $request->status);
        }

        return response()->json($query->paginate($request->per_page ?? 20));
    }
}

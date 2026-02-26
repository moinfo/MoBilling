<?php

namespace App\Http\Controllers;

use App\Models\CommunicationLog;
use App\Models\CronLog;
use Carbon\Carbon;
use Illuminate\Http\Request;

class AutomationController extends Controller
{
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
        $query = CommunicationLog::query()->orderByDesc('created_at');

        if ($request->has('date')) {
            $date = Carbon::parse($request->date);
            $query->whereBetween('created_at', [$date->startOfDay(), $date->copy()->endOfDay()]);
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

<?php

namespace App\Http\Controllers;

use App\Models\SatisfactionCall;
use Carbon\Carbon;
use Illuminate\Http\Request;

class SatisfactionCallController extends Controller
{
    /**
     * Dashboard: today's calls, overdue, month stats + avg rating.
     */
    public function dashboard()
    {
        $monthKey = Carbon::today()->format('Y-m');

        $dueToday = SatisfactionCall::with(['client', 'user'])
            ->scheduledToday()
            ->orderBy('scheduled_date')
            ->get();

        $overdue = SatisfactionCall::with(['client', 'user'])
            ->overdue()
            ->orderBy('scheduled_date')
            ->get();

        $monthStats = SatisfactionCall::forMonth($monthKey);
        $completedThisMonth = (clone $monthStats)->where('status', 'completed')->count();
        $totalThisMonth = (clone $monthStats)->count();
        $avgRating = (clone $monthStats)->where('status', 'completed')->whereNotNull('rating')->avg('rating');

        $format = fn ($c) => [
            'id' => $c->id,
            'client_id' => $c->client_id,
            'client_name' => $c->client?->name,
            'client_phone' => $c->client?->phone,
            'user_id' => $c->user_id,
            'assigned_to' => $c->user?->name,
            'scheduled_date' => $c->scheduled_date->toDateString(),
            'called_at' => $c->called_at?->toISOString(),
            'outcome' => $c->outcome,
            'rating' => $c->rating,
            'feedback' => $c->feedback,
            'internal_notes' => $c->internal_notes,
            'status' => $c->status,
            'month_key' => $c->month_key,
        ];

        return response()->json([
            'data' => [
                'due_today' => $dueToday->map($format)->values(),
                'overdue' => $overdue->map($format)->values(),
                'stats' => [
                    'due_today' => $dueToday->count(),
                    'overdue' => $overdue->count(),
                    'completed_this_month' => $completedThisMonth,
                    'total_this_month' => $totalThisMonth,
                    'avg_rating' => $avgRating ? round((float) $avgRating, 1) : null,
                ],
            ],
        ]);
    }

    /**
     * Paginated history with filters.
     */
    public function index(Request $request)
    {
        $query = SatisfactionCall::with(['client', 'user'])
            ->orderByDesc('scheduled_date');

        if ($request->has('status') && $request->status !== 'all') {
            $query->where('status', $request->status);
        }

        if ($request->has('outcome') && $request->outcome !== 'all') {
            $query->where('outcome', $request->outcome);
        }

        if ($request->has('month')) {
            $query->where('month_key', $request->month);
        }

        if ($request->has('client_id')) {
            $query->where('client_id', $request->client_id);
        }

        $calls = $query->paginate($request->get('per_page', 20));

        $calls->getCollection()->transform(fn ($c) => [
            'id' => $c->id,
            'client_id' => $c->client_id,
            'client_name' => $c->client?->name,
            'client_phone' => $c->client?->phone,
            'assigned_to' => $c->user?->name,
            'user_id' => $c->user_id,
            'scheduled_date' => $c->scheduled_date->toDateString(),
            'called_at' => $c->called_at?->toISOString(),
            'outcome' => $c->outcome,
            'rating' => $c->rating,
            'feedback' => $c->feedback,
            'internal_notes' => $c->internal_notes,
            'status' => $c->status,
            'month_key' => $c->month_key,
            'created_at' => $c->created_at?->toISOString(),
        ]);

        return response()->json($calls);
    }

    /**
     * Record call outcome, rating, feedback.
     */
    public function logCall(Request $request, SatisfactionCall $satisfactionCall)
    {
        $data = $request->validate([
            'outcome' => 'required|in:satisfied,needs_improvement,complaint,suggestion,no_answer,unreachable',
            'rating' => 'nullable|integer|min:1|max:5',
            'feedback' => 'nullable|string|max:2000',
            'internal_notes' => 'nullable|string|max:2000',
        ]);

        $satisfactionCall->update([
            'called_at' => now(),
            'user_id' => auth()->id(),
            'outcome' => $data['outcome'],
            'rating' => $data['rating'] ?? null,
            'feedback' => $data['feedback'] ?? null,
            'internal_notes' => $data['internal_notes'] ?? null,
            'status' => 'completed',
        ]);

        return response()->json([
            'data' => $satisfactionCall->fresh(),
            'message' => 'Satisfaction call logged.',
        ]);
    }

    /**
     * Reschedule a call to a different date.
     */
    public function reschedule(Request $request, SatisfactionCall $satisfactionCall)
    {
        $data = $request->validate([
            'scheduled_date' => 'required|date|after_or_equal:today',
        ]);

        $satisfactionCall->update([
            'scheduled_date' => $data['scheduled_date'],
            'status' => 'scheduled',
        ]);

        return response()->json([
            'data' => $satisfactionCall->fresh(),
            'message' => 'Call rescheduled to ' . $data['scheduled_date'] . '.',
        ]);
    }

    /**
     * Cancel a satisfaction call.
     */
    public function cancel(SatisfactionCall $satisfactionCall)
    {
        $satisfactionCall->update(['status' => 'cancelled']);

        return response()->json(['message' => 'Satisfaction call cancelled.']);
    }

    /**
     * Client history — last 24 months of calls.
     */
    public function clientHistory(string $clientId)
    {
        $calls = SatisfactionCall::with(['user'])
            ->where('client_id', $clientId)
            ->orderByDesc('scheduled_date')
            ->limit(24)
            ->get()
            ->map(fn ($c) => [
                'id' => $c->id,
                'assigned_to' => $c->user?->name,
                'scheduled_date' => $c->scheduled_date->toDateString(),
                'called_at' => $c->called_at?->toISOString(),
                'outcome' => $c->outcome,
                'rating' => $c->rating,
                'feedback' => $c->feedback,
                'internal_notes' => $c->internal_notes,
                'status' => $c->status,
                'month_key' => $c->month_key,
            ]);

        return response()->json(['data' => $calls]);
    }
}

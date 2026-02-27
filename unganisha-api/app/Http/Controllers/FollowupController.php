<?php

namespace App\Http\Controllers;

use App\Models\Document;
use App\Models\Followup;
use Carbon\Carbon;
use Illuminate\Http\Request;

class FollowupController extends Controller
{
    /**
     * Dashboard data: calls due today + overdue follow-ups.
     */
    public function dashboard()
    {
        $today = Carbon::today();

        $dueToday = Followup::with(['client', 'document', 'user'])
            ->whereHas('document')
            ->dueToday()
            ->orderBy('next_followup')
            ->get();

        $overdueFollowups = Followup::with(['client', 'document', 'user'])
            ->whereHas('document')
            ->overdue()
            ->orderBy('next_followup')
            ->get();

        $format = function ($f) {
            return [
                'id' => $f->id,
                'document_id' => $f->document_id,
                'document_number' => $f->document?->document_number,
                'client_id' => $f->client_id,
                'client_name' => $f->client?->name,
                'client_phone' => $f->client?->phone,
                'invoice_total' => (float) ($f->document?->total ?? 0),
                'invoice_balance' => (float) ($f->document?->balance_due ?? 0),
                'assigned_to' => $f->user?->name,
                'user_id' => $f->user_id,
                'call_date' => $f->call_date?->toISOString(),
                'outcome' => $f->outcome,
                'notes' => $f->notes,
                'promise_date' => $f->promise_date?->toDateString(),
                'promise_amount' => $f->promise_amount ? (float) $f->promise_amount : null,
                'next_followup' => $f->next_followup?->toDateString(),
                'status' => $f->status,
                'call_count' => Followup::where('document_id', $f->document_id)
                    ->whereNotNull('call_date')
                    ->count(),
            ];
        };

        return response()->json([
            'data' => [
                'due_today' => $dueToday->map($format)->values(),
                'overdue_followups' => $overdueFollowups->map($format)->values(),
                'stats' => [
                    'due_today' => $dueToday->count(),
                    'overdue' => $overdueFollowups->count(),
                    'total_active' => Followup::active()->whereHas('document')->count(),
                ],
            ],
        ]);
    }

    /**
     * Full follow-up history with filters.
     */
    public function index(Request $request)
    {
        $query = Followup::with(['client', 'document', 'user'])
            ->orderByDesc('created_at');

        if ($request->has('status') && $request->status !== 'all') {
            $query->where('status', $request->status);
        }

        if ($request->has('outcome') && $request->outcome !== 'all') {
            $query->where('outcome', $request->outcome);
        }

        if ($request->has('client_id')) {
            $query->where('client_id', $request->client_id);
        }

        if ($request->has('document_id')) {
            $query->where('document_id', $request->document_id);
        }

        if ($request->has('user_id')) {
            $query->where('user_id', $request->user_id);
        }

        if ($request->has('date_from')) {
            $query->whereDate('created_at', '>=', $request->date_from);
        }

        if ($request->has('date_to')) {
            $query->whereDate('created_at', '<=', $request->date_to);
        }

        $followups = $query->paginate($request->get('per_page', 20));

        $followups->getCollection()->transform(fn ($f) => [
            'id' => $f->id,
            'document_id' => $f->document_id,
            'document_number' => $f->document?->document_number,
            'client_id' => $f->client_id,
            'client_name' => $f->client?->name,
            'client_phone' => $f->client?->phone,
            'assigned_to' => $f->user?->name,
            'user_id' => $f->user_id,
            'invoice_total' => (float) ($f->document?->total ?? 0),
            'invoice_balance' => (float) ($f->document?->balance_due ?? 0),
            'call_date' => $f->call_date?->toISOString(),
            'outcome' => $f->outcome,
            'notes' => $f->notes,
            'promise_date' => $f->promise_date?->toDateString(),
            'promise_amount' => $f->promise_amount ? (float) $f->promise_amount : null,
            'next_followup' => $f->next_followup?->toDateString(),
            'status' => $f->status,
            'created_at' => $f->created_at?->toISOString(),
        ]);

        return response()->json($followups);
    }

    /**
     * Create a follow-up reminder for an invoice (schedule a call).
     */
    public function store(Request $request)
    {
        $data = $request->validate([
            'document_id' => 'required|uuid|exists:documents,id',
            'next_followup' => 'required|date',
            'user_id' => 'nullable|uuid|exists:users,id',
            'notes' => 'nullable|string|max:1000',
        ]);

        $document = Document::findOrFail($data['document_id']);

        // Check max 3 calls
        $callCount = Followup::where('document_id', $document->id)
            ->whereNotNull('call_date')
            ->count();

        if ($callCount >= 3) {
            return response()->json([
                'message' => 'Maximum 3 follow-up calls reached for this invoice. It has been escalated.',
            ], 422);
        }

        $followup = Followup::create([
            'document_id' => $document->id,
            'client_id' => $document->client_id,
            'user_id' => $data['user_id'] ?? auth()->id(),
            'next_followup' => $data['next_followup'],
            'notes' => $data['notes'] ?? null,
            'status' => 'pending',
        ]);

        return response()->json([
            'data' => $followup,
            'message' => 'Follow-up scheduled.',
        ], 201);
    }

    /**
     * Log a call — record outcome, notes, and auto-schedule next follow-up.
     */
    public function logCall(Request $request, Followup $followup)
    {
        $data = $request->validate([
            'outcome' => 'required|in:promised,declined,no_answer,disputed,partial_payment',
            'notes' => 'required|string|max:2000',
            'promise_date' => 'nullable|date|after:today',
            'promise_amount' => 'nullable|numeric|min:0',
            'next_followup_override' => 'nullable|date|after:today',
        ]);

        $today = Carbon::today();

        // Update this follow-up with call details
        $followup->update([
            'call_date' => now(),
            'user_id' => auth()->id(),
            'outcome' => $data['outcome'],
            'notes' => $data['notes'],
            'promise_date' => $data['promise_date'] ?? null,
            'promise_amount' => $data['promise_amount'] ?? null,
            'status' => 'open',
        ]);

        // Count total calls for this invoice
        $callCount = Followup::where('document_id', $followup->document_id)
            ->whereNotNull('call_date')
            ->count();

        // If max calls reached, escalate instead of scheduling more
        if ($callCount >= 3) {
            $followup->update(['status' => 'escalated']);

            return response()->json([
                'data' => $followup->fresh(),
                'message' => 'Call logged. Maximum 3 calls reached — invoice escalated.',
                'escalated' => true,
            ]);
        }

        // Auto-schedule next follow-up based on outcome
        $nextDate = $data['next_followup_override']
            ? Carbon::parse($data['next_followup_override'])
            : match ($data['outcome']) {
                'promised' => $data['promise_date']
                    ? Carbon::parse($data['promise_date'])->addDay()
                    : $today->copy()->addDays(3),
                'no_answer' => $today->copy()->addDays(2),
                'declined' => $today->copy()->addDays(5),
                'disputed' => $today->copy()->addDays(5),
                'partial_payment' => $today->copy()->addDays(7),
            };

        $nextFollowup = Followup::create([
            'document_id' => $followup->document_id,
            'client_id' => $followup->client_id,
            'user_id' => auth()->id(),
            'next_followup' => $nextDate,
            'notes' => "Auto-scheduled after call #{$callCount} (outcome: {$data['outcome']})",
            'status' => 'pending',
        ]);

        $followup->update(['next_followup' => null]);

        return response()->json([
            'data' => $followup->fresh(),
            'next_followup' => $nextFollowup,
            'message' => "Call logged. Next follow-up scheduled for {$nextDate->toDateString()}.",
            'escalated' => false,
        ]);
    }

    /**
     * Cancel a follow-up.
     */
    public function cancel(Followup $followup)
    {
        $followup->update(['status' => 'cancelled']);

        return response()->json(['message' => 'Follow-up cancelled.']);
    }

    /**
     * Get follow-up history for a specific client.
     */
    public function clientHistory(string $clientId)
    {
        $followups = Followup::with(['document', 'user'])
            ->where('client_id', $clientId)
            ->orderByDesc('created_at')
            ->limit(50)
            ->get()
            ->map(fn ($f) => [
                'id' => $f->id,
                'document_number' => $f->document?->document_number,
                'assigned_to' => $f->user?->name,
                'call_date' => $f->call_date?->toISOString(),
                'outcome' => $f->outcome,
                'notes' => $f->notes,
                'promise_date' => $f->promise_date?->toDateString(),
                'promise_amount' => $f->promise_amount ? (float) $f->promise_amount : null,
                'next_followup' => $f->next_followup?->toDateString(),
                'status' => $f->status,
                'created_at' => $f->created_at?->toISOString(),
            ]);

        return response()->json(['data' => $followups]);
    }
}

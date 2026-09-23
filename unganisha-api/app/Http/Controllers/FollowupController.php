<?php

namespace App\Http\Controllers;

use App\Models\Document;
use App\Models\Followup;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class FollowupController extends Controller
{
    /**
     * Dashboard data: calls due today + overdue follow-ups.
     */
    public function dashboard()
    {
        $today = Carbon::today();

        $notCancelled = fn ($q) => $q->where('status', '!=', 'cancelled');

        $withDocSum = ['client', 'document' => fn ($q) => $q->withSum('payments', 'amount')->withSum('refunds', 'amount'), 'user'];

        $dueToday = Followup::with($withDocSum)
            ->whereHas('document', $notCancelled)
            ->dueToday()
            ->orderBy('next_followup')
            ->get();

        $overdueFollowups = Followup::with($withDocSum)
            ->whereHas('document', $notCancelled)
            ->overdue()
            ->orderBy('next_followup')
            ->get();

        // Pre-compute call counts per invoice in a single grouped query — avoids
        // running one COUNT per followup row across both lists (N+1).
        $callCounts = Followup::whereIn(
                'document_id',
                $dueToday->pluck('document_id')->merge($overdueFollowups->pluck('document_id'))->unique()->all()
            )
            ->whereNotNull('call_date')
            ->selectRaw('document_id, COUNT(*) as aggregate')
            ->groupBy('document_id')
            ->pluck('aggregate', 'document_id');

        $format = function ($f) use ($callCounts) {
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
                'call_count' => (int) ($callCounts[$f->document_id] ?? 0),
            ];
        };

        return response()->json([
            'data' => [
                'due_today' => $dueToday->map($format)->values(),
                'overdue_followups' => $overdueFollowups->map($format)->values(),
                'stats' => [
                    'due_today' => $dueToday->count(),
                    'overdue' => $overdueFollowups->count(),
                    'total_active' => Followup::active()->whereHas('document', $notCancelled)->count(),
                ],
            ],
        ]);
    }

    /**
     * Full follow-up history with filters.
     */
    public function index(Request $request)
    {
        $query = Followup::with(['client', 'document' => fn ($q) => $q->withSum('payments', 'amount')->withSum('refunds', 'amount'), 'user'])
            ->whereHas('document', fn ($q) => $q->where('status', '!=', 'cancelled'))
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

        if ($error = $this->assignmentBlocker($document)) {
            return response()->json(['message' => $error], 422);
        }

        $followup = Followup::create([
            'document_id' => $document->id,
            'client_id' => $document->client_id,
            'user_id' => $data['user_id'] ?? auth()->id(),
            'next_followup' => $data['next_followup'],
            'notes' => $data['notes'] ?? null,
            'status' => 'pending',
        ]);

        if ($followup->user_id !== auth()->id()) {
            $this->notifyAssignment($followup->user_id, [$document], Carbon::parse($data['next_followup'])->format('d M Y'));
        }

        return response()->json([
            'data' => $followup,
            'message' => 'Follow-up scheduled.',
        ], 201);
    }

    /**
     * One summary notification per staff member for the invoices just assigned to them.
     * Never allowed to break the assignment itself.
     *
     * @param  Document[]  $docs
     */
    private function notifyAssignment(string $userId, array $docs, string $nextDate): void
    {
        try {
            $user = \App\Models\User::find($userId);
            $tenant = $user?->tenant;
            if (!$user || !$tenant || !$docs) {
                return;
            }
            $items = [];
            $total = 0.0;
            foreach ($docs as $i => $d) {
                $balance = (float) $d->balance_due;
                $total += $balance;
                if ($i < 5) {
                    $items[] = [
                        'client' => $d->client?->name ?? '-',
                        'invoice' => $d->document_number,
                        'balance' => $balance,
                        'next' => $nextDate,
                    ];
                }
            }
            $user->notify(new \App\Notifications\FollowupAssignedNotification(
                $tenant, auth()->user()?->name ?? 'Admin', $items, count($docs), $total,
            ));
        } catch (\Throwable $e) {
            \Illuminate\Support\Facades\Log::warning('Followup assignment notification failed', ['error' => $e->getMessage()]);
        }
    }

    /**
     * Shared rules for assigning an invoice to staff. Returns an error message, or null when assignable.
     * An admin must have reviewed/approved the invoice (DocumentController::approveForCollection),
     * and at most 3 logged calls are allowed per invoice.
     */
    private function assignmentBlocker(Document $document): ?string
    {
        if (!$document->collection_reviewed_at) {
            return 'This invoice has not been reviewed and approved for collection yet. An admin must approve it first.';
        }

        $callCount = Followup::where('document_id', $document->id)->whereNotNull('call_date')->count();
        if ($callCount >= 3) {
            return 'Maximum 3 follow-up calls reached for this invoice. It has been escalated.';
        }

        return null;
    }

    private function balanceSql(): string
    {
        return '(documents.total - (COALESCE((SELECT SUM(p.amount) FROM payments_in p WHERE p.document_id = documents.id), 0)'
            . ' - COALESCE((SELECT SUM(r.amount) FROM refunds r WHERE r.document_id = documents.id), 0)))';
    }

    /**
     * Unpaid invoices with no active follow-up (nobody is working them). Escalated ones are included and flagged.
     */
    public function unassigned(Request $request)
    {
        $balanceSql = $this->balanceSql();
        $daysSql = 'CASE WHEN documents.due_date IS NULL THEN 0 ELSE GREATEST(DATEDIFF(CURDATE(), documents.due_date), 0) END';

        $base = Document::query()
            ->where('documents.type', 'invoice')
            ->whereIn('documents.status', ['sent', 'overdue', 'partial'])
            ->whereRaw("$balanceSql > 0")
            ->whereDoesntHave('followups', fn ($q) => $q->whereIn('status', ['pending', 'open', 'broken']));

        $filtered = clone $base;

        if ($search = trim((string) $request->get('search', ''))) {
            $like = '%' . str_replace(['%', '_'], ['\%', '\_'], $search) . '%';
            $filtered->where(fn ($q) => $q->where('documents.document_number', 'like', $like)
                ->orWhereHas('client', fn ($c) => $c->where('name', 'like', $like)));
        }
        if ($request->filled('min_balance')) {
            $filtered->whereRaw("$balanceSql >= ?", [(float) $request->min_balance]);
        }
        if ($request->filled('min_days_overdue')) {
            $filtered->whereRaw("$daysSql >= ?", [(int) $request->min_days_overdue]);
        }
        $review = $request->get('review', 'all');
        if ($review === 'approved') {
            $filtered->whereNotNull('documents.collection_reviewed_at');
        } elseif ($review === 'not_reviewed') {
            $filtered->whereNull('documents.collection_reviewed_at');
        }

        $summaryRow = (clone $filtered)->selectRaw(
            "COUNT(*) as total, COALESCE(SUM($balanceSql), 0) as total_balance, "
            . "COALESCE(SUM(documents.collection_reviewed_at IS NULL), 0) as not_reviewed"
        )->reorder()->first();

        $perPage = min(max((int) $request->get('per_page', 25), 1), 100);

        $page = $filtered
            ->select('documents.*')
            ->with(['client:id,name,phone', 'collectionReviewedBy:id,name'])
            ->withSum('payments', 'amount')->withSum('refunds', 'amount')
            ->withCount(['followups as escalated_count' => fn ($q) => $q->where('status', 'escalated')])
            ->withCount(['followups as call_count' => fn ($q) => $q->whereNotNull('call_date')])
            ->orderByRaw('documents.due_date IS NULL')
            ->orderBy('documents.due_date')
            ->orderBy('documents.document_number')
            ->paginate($perPage);

        $today = Carbon::today();
        $page->getCollection()->transform(fn ($d) => [
            'id' => $d->id,
            'document_number' => $d->document_number,
            'client_id' => $d->client_id,
            'client_name' => $d->client?->name,
            'client_phone' => $d->client?->phone,
            'total' => (float) $d->total,
            'paid' => (float) $d->paid_amount,
            'balance_due' => (float) $d->balance_due,
            'due_date' => $d->due_date?->toDateString(),
            'days_overdue' => $d->due_date ? max((int) $d->due_date->startOfDay()->diffInDays($today, false), 0) : 0,
            'status' => $d->status,
            'collection_reviewed_at' => $d->collection_reviewed_at?->toISOString(),
            'collection_reviewed_by_name' => $d->collectionReviewedBy?->name,
            'escalated' => (int) $d->escalated_count > 0,
            'call_count' => (int) $d->call_count,
        ]);

        return response()->json(array_merge($page->toArray(), [
            'summary' => [
                'total' => (int) $summaryRow->total,
                'total_balance' => (float) $summaryRow->total_balance,
                'not_reviewed' => (int) $summaryRow->not_reviewed,
            ],
        ]));
    }

    /**
     * Assign many approved invoices to one staff member. Skips (with reasons) any that fail the store() rules.
     */
    public function bulkAssign(Request $request)
    {
        $data = $request->validate([
            'document_ids' => 'required|array|min:1|max:200',
            'document_ids.*' => 'uuid',
            'user_id' => 'required|uuid|exists:users,id',
            'next_followup' => 'required|date',
            'notes' => 'nullable|string|max:1000',
        ]);

        $docs = Document::whereIn('id', $data['document_ids'])->get()->keyBy('id');
        $assigned = [];
        $skipped = [];

        DB::transaction(function () use ($data, $docs, &$assigned, &$skipped) {
            foreach (array_unique($data['document_ids']) as $id) {
                $doc = $docs->get($id);
                if (!$doc) {
                    $skipped[] = ['document_id' => $id, 'document_number' => null, 'reason' => 'Invoice not found.'];
                    continue;
                }
                $reason = null;
                if ($doc->type !== 'invoice' || !in_array($doc->status, ['sent', 'overdue', 'partial'], true)) {
                    $reason = 'Only sent, overdue or partially paid invoices can be assigned.';
                } elseif (Followup::where('document_id', $doc->id)->active()->exists()) {
                    $reason = 'Already assigned (active follow-up exists).';
                } else {
                    $reason = $this->assignmentBlocker($doc);
                }
                if ($reason) {
                    $skipped[] = ['document_id' => $id, 'document_number' => $doc->document_number, 'reason' => $reason];
                    continue;
                }
                Followup::create([
                    'document_id' => $doc->id,
                    'client_id' => $doc->client_id,
                    'user_id' => $data['user_id'],
                    'next_followup' => $data['next_followup'],
                    'notes' => $data['notes'] ?? null,
                    'status' => 'pending',
                ]);
                $assigned[] = $id;
            }
        });

        if ($assigned && $data['user_id'] !== auth()->id()) {
            $this->notifyAssignment(
                $data['user_id'],
                array_map(fn ($id) => $docs->get($id), $assigned),
                Carbon::parse($data['next_followup'])->format('d M Y'),
            );
        }

        return response()->json([
            'assigned' => $assigned,
            'skipped' => $skipped,
            'message' => count($assigned) . ' invoice(s) assigned, ' . count($skipped) . ' skipped.',
        ]);
    }

    /**
     * Log a call — record outcome, notes, and auto-schedule next follow-up.
     */
    public function logCall(Request $request, Followup $followup)
    {
        $data = $request->validate([
            'outcome' => 'required|in:promised,declined,no_answer,disputed,partial_payment',
            'notes' => 'required|string|max:2000',
            // A "promised" outcome drives next_followup off promise_date, so require it.
            // Both "promised" and "partial_payment" should carry a real amount.
            'promise_date' => 'required_if:outcome,promised|nullable|date|after:today',
            'promise_amount' => 'required_if:outcome,promised,partial_payment|nullable|numeric|min:0.01',
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

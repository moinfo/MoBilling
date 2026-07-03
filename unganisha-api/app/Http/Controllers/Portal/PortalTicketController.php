<?php

namespace App\Http\Controllers\Portal;

use App\Http\Controllers\Controller;
use App\Http\Controllers\TicketController;
use App\Models\Ticket;
use App\Notifications\TicketActivityStaffNotification;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\Rule;

class PortalTicketController extends Controller
{
    public function index(Request $request)
    {
        $tickets = Ticket::where('client_id', $request->user()->client_id)
            ->withCount('replies')
            ->orderByRaw("CASE WHEN status = 'closed' THEN 1 ELSE 0 END")
            ->orderByDesc('last_reply_at')
            ->get()
            ->map(fn ($t) => $this->format($t));

        return response()->json(['data' => $tickets]);
    }

    public function store(Request $request)
    {
        $user = $request->user();

        $data = $request->validate([
            'subject'  => 'required|string|max:255',
            'message'  => 'required|string|max:10000',
            'priority' => ['nullable', Rule::in(Ticket::PRIORITIES)],
        ]);

        $ticket = Ticket::create([
            'tenant_id'     => $user->tenant_id,
            'client_id'     => $user->client_id,
            'ticket_number' => Ticket::nextNumber($user->tenant_id),
            'subject'       => $data['subject'],
            'status'        => 'open',
            'priority'      => $data['priority'] ?? 'medium',
            'opened_by'     => $user->id,
            'last_reply_at' => now(),
        ]);

        $ticket->replies()->create([
            'tenant_id'      => $user->tenant_id,
            'author_type'    => 'client',
            'client_user_id' => $user->id,
            'message'        => $data['message'],
        ]);

        $this->notifyStaff($ticket, 'opened');

        return response()->json([
            'data'    => $this->format($ticket->fresh()),
            'message' => "Ticket {$ticket->ticket_number} opened — we'll get back to you shortly.",
        ], 201);
    }

    public function show(Request $request, Ticket $ticket)
    {
        abort_unless($ticket->client_id === $request->user()->client_id, 404);

        $ticket->load(['replies.user:id,name', 'replies.clientUser:id,name']);

        return response()->json(['data' => $this->format($ticket, withReplies: true)]);
    }

    public function reply(Request $request, Ticket $ticket)
    {
        abort_unless($ticket->client_id === $request->user()->client_id, 404);

        $data = $request->validate(['message' => 'required|string|max:10000']);

        $ticket->replies()->create([
            'tenant_id'      => $ticket->tenant_id,
            'author_type'    => 'client',
            'client_user_id' => $request->user()->id,
            'message'        => $data['message'],
        ]);

        // A client reply reopens a closed ticket.
        $ticket->update(['status' => 'customer_reply', 'last_reply_at' => now()]);

        $this->notifyStaff($ticket, 'client_reply');

        $ticket->load(['replies.user:id,name', 'replies.clientUser:id,name']);

        return response()->json(['data' => $this->format($ticket, withReplies: true)]);
    }

    public function close(Request $request, Ticket $ticket)
    {
        abort_unless($ticket->client_id === $request->user()->client_id, 404);

        $ticket->update(['status' => 'closed']);

        return response()->json(['data' => $this->format($ticket->fresh())]);
    }

    private function notifyStaff(Ticket $ticket, string $event): void
    {
        try {
            foreach (TicketController::staffToNotify($ticket) as $staff) {
                $staff->notify(new TicketActivityStaffNotification($ticket, $event));
            }
        } catch (\Throwable $e) {
            Log::warning("Ticket staff notification failed for {$ticket->ticket_number}: {$e->getMessage()}");
        }
    }

    private function format(Ticket $t, bool $withReplies = false): array
    {
        $out = [
            'id'            => $t->id,
            'ticket_number' => $t->ticket_number,
            'subject'       => $t->subject,
            'status'        => $t->status,
            'priority'      => $t->priority,
            'replies_count' => $t->replies_count ?? null,
            'last_reply_at' => $t->last_reply_at?->toISOString(),
            'created_at'    => $t->created_at->toISOString(),
        ];

        if ($withReplies) {
            $out['replies'] = $t->replies->map(fn ($r) => [
                'id'          => $r->id,
                'author_type' => $r->author_type,
                'author_name' => $r->authorName(),
                'message'     => $r->message,
                'created_at'  => $r->created_at->toISOString(),
            ])->values();
        }

        return $out;
    }
}

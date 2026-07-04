<?php

namespace App\Http\Controllers;

use App\Models\Ticket;
use App\Models\TicketAttachment;
use App\Models\User;
use App\Notifications\TicketRepliedNotification;
use App\Traits\HandlesTicketAttachments;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\Rule;

class TicketController extends Controller
{
    use HandlesTicketAttachments;

    public function index(Request $request)
    {
        $query = Ticket::with(['client:id,name', 'assignee:id,name'])
            ->withCount('replies')
            ->orderByRaw("CASE status WHEN 'customer_reply' THEN 0 WHEN 'open' THEN 1 WHEN 'answered' THEN 2 ELSE 3 END")
            ->orderByDesc('last_reply_at');

        if ($request->filled('status')) $query->where('status', $request->status);
        if ($request->filled('search')) {
            $s = $request->search;
            $query->where(fn ($q) => $q
                ->where('subject', 'like', "%{$s}%")
                ->orWhere('ticket_number', 'like', "%{$s}%")
                ->orWhereHas('client', fn ($c) => $c->where('name', 'like', "%{$s}%")));
        }

        return response()->json(['data' => $query->paginate($request->get('per_page', 20))]);
    }

    public function stats()
    {
        return response()->json([
            'awaiting_reply' => Ticket::whereIn('status', ['open', 'customer_reply'])->count(),
            'answered'       => Ticket::where('status', 'answered')->count(),
            'closed'         => Ticket::where('status', 'closed')->count(),
        ]);
    }

    public function show(Ticket $ticket)
    {
        $ticket->load(['client:id,name,email', 'assignee:id,name', 'openedBy:id,name', 'replies.user:id,name', 'replies.clientUser:id,name', 'replies.attachments']);

        return response()->json(['data' => $this->format($ticket, withReplies: true)]);
    }

    public function reply(Request $request, Ticket $ticket)
    {
        $data = $request->validate(array_merge(
            ['message' => 'required|string|max:10000'],
            $this->attachmentValidationRules(),
        ));

        $reply = $ticket->replies()->create([
            'tenant_id'   => $ticket->tenant_id,
            'author_type' => 'staff',
            'user_id'     => auth()->id(),
            'message'     => $data['message'],
        ]);

        $this->storeReplyAttachments($request, $ticket, $reply);

        $ticket->update([
            'status'        => 'answered',
            'last_reply_at' => now(),
            'assigned_to'   => $ticket->assigned_to ?? auth()->id(),
        ]);

        $this->notifyClient($ticket, $data['message']);

        return response()->json(['data' => $this->format($ticket->fresh(['replies.user:id,name', 'replies.clientUser:id,name', 'replies.attachments', 'client:id,name,email', 'assignee:id,name']), withReplies: true)]);
    }

    /** Stream a ticket attachment, scoped to the staff member's tenant. */
    public function downloadAttachment(TicketAttachment $attachment)
    {
        // The tenant global scope on TicketAttachment already blocks other
        // tenants; this is a defensive re-check.
        abort_unless($attachment->tenant_id === auth()->user()->tenant_id, 404);
        abort_unless(Storage::disk('local')->exists($attachment->path), 404);

        return Storage::disk('local')->download($attachment->path, $attachment->original_name);
    }

    public function updateStatus(Request $request, Ticket $ticket)
    {
        $data = $request->validate(['status' => ['required', Rule::in(['open', 'closed'])]]);

        $ticket->update(['status' => $data['status']]);

        if ($data['status'] === 'closed') {
            $this->notifyClient($ticket, 'This ticket has been closed.', closed: true);
        }

        return response()->json(['data' => $this->format($ticket->fresh(['client:id,name,email', 'assignee:id,name']))]);
    }

    public function assign(Request $request, Ticket $ticket)
    {
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'user_id' => ['nullable', 'uuid', Rule::exists('users', 'id')->where('tenant_id', $tenantId)->where('is_active', true)],
        ]);

        $ticket->update(['assigned_to' => $data['user_id'] ?? null]);

        return response()->json(['data' => $this->format($ticket->fresh(['client:id,name,email', 'assignee:id,name']))]);
    }

    private function notifyClient(Ticket $ticket, string $excerpt, bool $closed = false): void
    {
        try {
            $recipient = $ticket->openedBy ?? $ticket->client;
            if ($recipient?->email) {
                $recipient->notify(new TicketRepliedNotification($ticket, $excerpt, $closed));
            }
        } catch (\Throwable $e) {
            Log::warning("Ticket client notification failed for {$ticket->ticket_number}: {$e->getMessage()}");
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
            'client'        => $t->client ? ['id' => $t->client->id, 'name' => $t->client->name] : null,
            'assignee'      => $t->assignee ? ['id' => $t->assignee->id, 'name' => $t->assignee->name] : null,
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
                'attachments' => $r->attachments->map(fn ($a) => [
                    'id'            => $a->id,
                    'original_name' => $a->original_name,
                    'mime'          => $a->mime,
                    'size'          => $a->size,
                    // Authenticated streaming endpoint (see routes); the raw
                    // public-disk URL is intentionally not exposed.
                    'download_url'  => "/tickets/attachments/{$a->id}/download",
                ])->values(),
            ])->values();
        }

        return $out;
    }

    /** Users who should hear about ticket activity: the assignee, else ticket managers. */
    public static function staffToNotify(Ticket $ticket)
    {
        if ($ticket->assignee) {
            return collect([$ticket->assignee]);
        }

        return User::withoutGlobalScopes()
            ->where('tenant_id', $ticket->tenant_id)
            ->where('is_active', true)
            ->whereHas('role.permissions', fn ($q) => $q->where('name', 'tickets.manage'))
            ->get();
    }
}

<?php

namespace App\Http\Controllers\Portal;

use App\Http\Controllers\Controller;
use App\Models\Document;
use App\Notifications\InvoiceSentNotification;
use Illuminate\Http\Request;

class PortalDocumentController extends Controller
{
    public function index(Request $request)
    {
        $clientId = $request->user()->client_id;
        $type = $request->get('type', 'invoice');

        $query = Document::where('client_id', $clientId)
            ->where('type', $type)
            ->whereNotIn('status', ['draft', 'cancelled'])
            ->with(['items', 'payments'])
            ->orderByDesc('date');

        if ($request->filled('status')) {
            $query->where('status', $request->status);
        }

        if ($request->filled('search')) {
            $query->where('document_number', 'like', "%{$request->search}%");
        }

        $paginated = $query->paginate($request->get('per_page', 20));

        // One query for every open billing-cancellation ticket this client has,
        // instead of a per-row lookup — see Ticket::hasPendingCancellation().
        $pendingCancellations = \App\Models\Ticket::where('client_id', $clientId)
            ->where('department', 'billing')
            ->where('status', '!=', 'closed')
            ->pluck('related_service')->filter()->flip();

        // Append computed fields
        $paginated->getCollection()->transform(function ($doc) use ($pendingCancellations) {
            $lateFee = $doc->items
                ->filter(fn ($item) => str_contains($item->description ?? '', 'Late payment fee'))
                ->sum('total');

            $doc->setAttribute('late_fee', round($lateFee, 2));
            $doc->setAttribute('original_amount', round((float) $doc->total - $lateFee, 2));
            $doc->setAttribute('paid_amount', round((float) $doc->paid_amount, 2));
            $doc->setAttribute('balance_due', round((float) $doc->balance_due, 2));
            $doc->setAttribute('cancellation_requested', $pendingCancellations->has($doc->document_number));

            return $doc;
        });

        return response()->json($paginated);
    }

    public function downloadPdf(Request $request, Document $document)
    {
        abort_unless($document->client_id === $request->user()->client_id, 404);
        abort_if(in_array($document->status, ['draft']), 404);

        $document->load('items', 'client', 'tenant');

        $pdf = app(\App\Services\PdfService::class)->generate($document);

        return $pdf->download("{$document->document_number}.pdf");
    }

    public function show(Request $request, Document $document)
    {
        $clientId = $request->user()->client_id;

        if ($document->client_id !== $clientId) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $document->load('items', 'payments', 'client', 'tenant');
        $client = $document->client;
        $tenant = $document->tenant;
        // never serialize the full relations — client.notes / tenant config are staff-only
        $document->unsetRelation('client');
        $document->unsetRelation('tenant');

        $lateFee = $document->items
            ->filter(fn ($item) => str_contains($item->description ?? '', 'Late payment fee'))
            ->sum('total');

        $cancellationRequested = \App\Models\Ticket::hasPendingCancellation(
            $document->tenant_id, $document->client_id, $document->document_number
        );

        return response()->json([
            'data' => array_merge($document->toArray(), [
                'paid_amount'             => (float) $document->paid_amount,
                'balance_due'             => (float) $document->balance_due,
                'late_fee'                => round($lateFee, 2),
                'cancellation_requested'  => $cancellationRequested,
                // WHMCS-style invoice view panels
                'invoiced_to' => [
                    'name'    => $client?->name,
                    'address' => $client?->address,
                    'email'   => $client?->email,
                    'phone'   => $client?->phone,
                    'tax_id'  => $client?->tax_id,
                ],
                'pay_to' => [
                    'name'    => $tenant?->name,
                    'address' => $tenant?->address,
                    'email'   => $tenant?->email,
                    'phone'   => $tenant?->phone,
                    'tax_id'  => $tenant?->tax_id,
                ],
                // Offline payment instructions (bank / mobile money details)
                'payment_methods' => collect($tenant?->payment_methods ?? [])
                    ->filter(fn ($m) => !empty($m['details']))
                    ->values(),
            ]),
        ]);
    }

    public function resend(Request $request, Document $document)
    {
        $clientId = $request->user()->client_id;

        if ($document->client_id !== $clientId) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $document->load('client');
        $document->client->notify(new InvoiceSentNotification($document));

        return response()->json(['message' => 'Document sent to your registered contacts (email/SMS/WhatsApp).']);
    }

    /** Request cancellation — opens a billing ticket for staff to action (mirrors PortalHostingController). */
    public function requestCancellation(Request $request, Document $document)
    {
        $user = $request->user();
        abort_unless($document->client_id === $user->client_id, 404);
        abort_unless($user->role === 'admin', 403, 'Only portal administrators can do this.');
        abort_unless(in_array($document->status, ['sent', 'overdue', 'partial', 'pending_approval']), 422,
            'This invoice cannot be cancelled — it is already paid or cancelled.');
        abort_if(\App\Models\Ticket::hasPendingCancellation($user->tenant_id, $user->client_id, $document->document_number), 422,
            'A cancellation request for this invoice is already pending — check your Support Tickets.');

        $data = $request->validate(['reason' => 'required|string|max:2000']);

        $ticket = \App\Models\Ticket::create([
            'tenant_id'       => $user->tenant_id,
            'client_id'       => $user->client_id,
            'ticket_number'   => \App\Models\Ticket::nextNumber($user->tenant_id),
            'subject'         => "Cancellation request: {$document->document_number}",
            'department'      => 'billing',
            'related_service' => $document->document_number,
            'status'          => 'open',
            'priority'        => 'high',
            'opened_by'       => $user->id,
            'last_reply_at'   => now(),
        ]);

        $ticket->replies()->create([
            'tenant_id'      => $user->tenant_id,
            'author_type'    => 'client',
            'client_user_id' => $user->id,
            'message'        => "Invoice: {$document->document_number} (Tsh." . number_format((float) $document->balance_due, 2) . " balance due)\n\nReason:\n{$data['reason']}",
        ]);

        try {
            foreach (\App\Http\Controllers\TicketController::staffToNotify($ticket) as $staff) {
                $staff->notify(new \App\Notifications\TicketActivityStaffNotification($ticket, 'opened'));
            }
        } catch (\Throwable) {
            // notification failure must not block the request
        }

        return response()->json([
            'message' => "Cancellation request submitted as ticket {$ticket->ticket_number} — our team will confirm shortly.",
        ], 201);
    }
}

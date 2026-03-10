<?php

namespace App\Http\Controllers;

use App\Http\Requests\StoreDocumentRequest;
use App\Http\Resources\DocumentResource;
use App\Models\CommunicationLog;
use App\Models\Document;
use App\Models\DocumentItem;
use App\Models\Tenant;
use App\Notifications\RecurringInvoiceReminderNotification;
use App\Services\DocumentConversionService;
use App\Services\DocumentNumberService;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class DocumentController extends Controller
{
    public function index(Request $request)
    {
        $query = Document::with(['client', 'items:id,document_id,description']);

        if ($request->has('type')) {
            $query->where('type', $request->type);
        }

        if ($request->has('status')) {
            $status = $request->status;
            if ($status === 'sent') {
                // "Unpaid" = sent, overdue, or partially paid
                $query->whereIn('status', ['sent', 'overdue', 'partial']);
            } else {
                $query->where('status', $status);
            }
        }

        if ($request->has('search')) {
            $search = $request->search;
            $query->where(function ($q) use ($search) {
                $q->where('document_number', 'LIKE', "%{$search}%")
                  ->orWhereHas('client', fn ($cq) => $cq->where('name', 'LIKE', "%{$search}%"));
            });
        }

        // Add reminder count for invoices (count from communication_logs by document_id in metadata)
        if ($request->type === 'invoice') {
            $query->addSelect([
                'reminder_count' => CommunicationLog::selectRaw('COUNT(*)')
                    ->withoutGlobalScopes()
                    ->whereColumn('communication_logs.client_id', 'documents.client_id')
                    ->whereRaw("JSON_UNQUOTE(JSON_EXTRACT(communication_logs.metadata, '$.document_id')) = documents.id"),
            ]);
        }

        return DocumentResource::collection(
            $query->orderByDesc('created_at')->paginate($request->per_page ?? 20)
        );
    }

    public function store(StoreDocumentRequest $request)
    {
        return DB::transaction(function () use ($request) {
            $items = $request->items;
            $subtotal = 0;
            $discountTotal = 0;
            $taxAmount = 0;

            foreach ($items as &$item) {
                $lineBase = $item['quantity'] * $item['price'];
                $discountType = $item['discount_type'] ?? 'percent';
                $discountValue = $item['discount_value'] ?? 0;
                $lineDiscount = $discountType === 'flat'
                    ? min($discountValue, $lineBase)
                    : $lineBase * ($discountValue / 100);
                $lineAfterDiscount = $lineBase - $lineDiscount;
                $lineTax = $lineAfterDiscount * (($item['tax_percent'] ?? 0) / 100);
                $item['discount_type'] = $discountType;
                $item['discount_value'] = $discountValue;
                $item['tax_amount'] = round($lineTax, 2);
                $item['total'] = round($lineAfterDiscount + $lineTax, 2);
                $subtotal += $lineBase;
                $discountTotal += $lineDiscount;
                $taxAmount += $lineTax;
            }

            $document = Document::create([
                'client_id' => $request->client_id,
                'type' => $request->type,
                'document_number' => app(DocumentNumberService::class)
                    ->generate($request->type, auth()->user()->tenant_id),
                'date' => $request->date,
                'due_date' => $request->due_date,
                'subtotal' => round($subtotal, 2),
                'discount_amount' => round($discountTotal, 2),
                'tax_amount' => round($taxAmount, 2),
                'total' => round($subtotal - $discountTotal + $taxAmount, 2),
                'notes' => $request->notes,
                'status' => 'draft',
                'created_by' => auth()->id(),
            ]);

            foreach ($items as $item) {
                $document->items()->create($item);
            }

            return new DocumentResource($document->load('items', 'client'));
        });
    }

    public function show(Document $document)
    {
        return new DocumentResource($document->load('items', 'client', 'payments'));
    }

    public function update(StoreDocumentRequest $request, Document $document)
    {
        if ($document->status !== 'draft') {
            return response()->json(['message' => 'Only draft documents can be edited. Return to draft first.'], 422);
        }

        return DB::transaction(function () use ($request, $document) {
            $items = $request->items;
            $subtotal = 0;
            $discountTotal = 0;
            $taxAmount = 0;

            foreach ($items as &$item) {
                $lineBase = $item['quantity'] * $item['price'];
                $discountType = $item['discount_type'] ?? 'percent';
                $discountValue = $item['discount_value'] ?? 0;
                $lineDiscount = $discountType === 'flat'
                    ? min($discountValue, $lineBase)
                    : $lineBase * ($discountValue / 100);
                $lineAfterDiscount = $lineBase - $lineDiscount;
                $lineTax = $lineAfterDiscount * (($item['tax_percent'] ?? 0) / 100);
                $item['discount_type'] = $discountType;
                $item['discount_value'] = $discountValue;
                $item['tax_amount'] = round($lineTax, 2);
                $item['total'] = round($lineAfterDiscount + $lineTax, 2);
                $subtotal += $lineBase;
                $discountTotal += $lineDiscount;
                $taxAmount += $lineTax;
            }

            $document->update([
                'client_id' => $request->client_id,
                'date' => $request->date,
                'due_date' => $request->due_date,
                'subtotal' => round($subtotal, 2),
                'discount_amount' => round($discountTotal, 2),
                'tax_amount' => round($taxAmount, 2),
                'total' => round($subtotal - $discountTotal + $taxAmount, 2),
                'notes' => $request->notes,
            ]);

            $document->items()->delete();
            foreach ($items as $item) {
                $document->items()->create($item);
            }

            return new DocumentResource($document->load('items', 'client'));
        });
    }

    public function destroy(Document $document)
    {
        $document->delete();
        return response()->json(['message' => 'Document deleted']);
    }

    public function convert(Request $request, Document $document)
    {
        $request->validate(['target_type' => 'required|in:proforma,invoice']);

        $newDocument = app(DocumentConversionService::class)
            ->convert($document, $request->target_type);

        return new DocumentResource($newDocument);
    }

    public function downloadPdf(Document $document)
    {
        $document->load('items', 'client', 'tenant');

        $pdf = app(\App\Services\PdfService::class)->generate($document);

        return $pdf->download("{$document->document_number}.pdf");
    }

    public function send(Request $request, Document $document)
    {
        $document->load('client');

        if (!$document->client->email) {
            return response()->json(['message' => 'Client has no email address'], 422);
        }

        // Update status before sending so PDF shows correct status
        $document->update(['status' => 'sent']);
        $document->refresh();

        $document->client->notify(new \App\Notifications\InvoiceSentNotification($document));

        // Confirm to the sending user via in-app notification
        $request->user()->notify(new \App\Notifications\DocumentSentConfirmation($document));

        return response()->json(['message' => 'Document sent successfully']);
    }

    public function submitForApproval(Document $document)
    {
        if ($document->status !== 'draft') {
            return response()->json(['message' => 'Only draft documents can be submitted for approval.'], 422);
        }

        $document->update(['status' => 'pending_approval']);

        return response()->json([
            'data' => new DocumentResource($document->fresh()->load('items', 'client')),
            'message' => "{$document->document_number} submitted for approval.",
        ]);
    }

    public function approve(Request $request, Document $document)
    {
        if ($document->status !== 'pending_approval') {
            return response()->json(['message' => 'Only documents pending approval can be approved.'], 422);
        }

        $document->load('client');

        // Update status before sending so PDF shows correct status
        $document->update(['status' => 'sent']);
        $document->refresh();

        // Approve and auto-send to client
        if ($document->client->email) {
            $document->client->notify(new \App\Notifications\InvoiceSentNotification($document));

            $request->user()->notify(new \App\Notifications\DocumentSentConfirmation($document));

            return response()->json([
                'data' => new DocumentResource($document->fresh()->load('items', 'client')),
                'message' => "{$document->document_number} approved and sent to {$document->client->name}.",
            ]);
        }

        // No email — already marked as sent above
        return response()->json([
            'data' => new DocumentResource($document->fresh()->load('items', 'client')),
            'message' => "{$document->document_number} approved. Client has no email — send manually.",
        ]);
    }

    public function reject(Request $request, Document $document)
    {
        if ($document->status !== 'pending_approval') {
            return response()->json(['message' => 'Only documents pending approval can be rejected.'], 422);
        }

        $request->validate([
            'reason' => 'nullable|string|max:500',
        ]);

        $document->update(['status' => 'draft']);

        return response()->json([
            'data' => new DocumentResource($document->fresh()->load('items', 'client')),
            'message' => "{$document->document_number} rejected and returned to draft.",
        ]);
    }

    public function cancel(Document $document)
    {
        if ($document->status === 'paid') {
            return response()->json(['message' => 'Cannot cancel a fully paid document.'], 422);
        }

        if ($document->status === 'cancelled') {
            return response()->json(['message' => 'Document is already cancelled.'], 422);
        }

        // Prevent cancellation if there are partial payments
        if ((float) $document->paid_amount > 0) {
            return response()->json([
                'message' => 'Cannot cancel a document with existing payments. Remove payments first.',
            ], 422);
        }

        $document->update(['status' => 'cancelled']);

        // Notify client about cancellation via email/SMS
        $document->load('client');
        if ($document->client) {
            $document->client->notify(new \App\Notifications\InvoiceCancelledNotification($document));
        }

        return response()->json([
            'data' => new DocumentResource($document->fresh()->load('items', 'client')),
            'message' => "{$document->document_number} has been cancelled.",
        ]);
    }

    public function uncancel(Document $document)
    {
        if ($document->status !== 'cancelled') {
            return response()->json(['message' => 'Only cancelled documents can be restored.'], 422);
        }

        // Restore to 'sent' — if overdue, the cron will update it automatically
        $newStatus = $document->due_date && $document->due_date->lt(now()) ? 'overdue' : 'sent';
        $document->update(['status' => $newStatus]);

        return response()->json([
            'data' => new DocumentResource($document->fresh()->load('items', 'client')),
            'message' => "{$document->document_number} has been restored.",
        ]);
    }

    public function removeItem(Document $document, DocumentItem $item)
    {
        if ($document->status === 'paid') {
            return response()->json(['message' => 'Cannot modify a paid document.'], 422);
        }

        if ($document->status === 'cancelled') {
            return response()->json(['message' => 'Cannot modify a cancelled document.'], 422);
        }

        if ($item->document_id !== $document->id) {
            return response()->json(['message' => 'Item does not belong to this document.'], 422);
        }

        $remainingItems = $document->items()->where('id', '!=', $item->id)->count();
        if ($remainingItems === 0) {
            return response()->json(['message' => 'Cannot remove the last item. Cancel the invoice instead.'], 422);
        }

        return DB::transaction(function () use ($document, $item) {
            $item->delete();

            // Recalculate totals from remaining items
            $subtotal = 0;
            $discountTotal = 0;
            $taxAmount = 0;

            foreach ($document->items()->get() as $remaining) {
                $lineBase = $remaining->quantity * $remaining->price;
                $lineDiscount = $remaining->discount_type === 'flat'
                    ? min($remaining->discount_value, $lineBase)
                    : $lineBase * ($remaining->discount_value / 100);
                $subtotal += $lineBase;
                $discountTotal += $lineDiscount;
                $taxAmount += $remaining->tax_amount;
            }

            $document->update([
                'subtotal' => round($subtotal, 2),
                'discount_amount' => round($discountTotal, 2),
                'tax_amount' => round($taxAmount, 2),
                'total' => round($subtotal - $discountTotal + $taxAmount, 2),
            ]);

            return response()->json([
                'data' => new DocumentResource($document->fresh()->load('items', 'client', 'payments')),
                'message' => "Item removed. Invoice total updated.",
            ]);
        });
    }

    public function merge(Request $request)
    {
        $request->validate([
            'document_ids' => 'required|array|min:2',
            'document_ids.*' => 'uuid',
        ]);

        $documents = Document::whereIn('id', $request->document_ids)
            ->where('type', 'invoice')
            ->whereNotIn('status', ['paid', 'cancelled'])
            ->with('items', 'client')
            ->get();

        if ($documents->count() < 2) {
            return response()->json(['message' => 'At least 2 unpaid invoices are required to merge.'], 422);
        }

        // All invoices must belong to the same client
        $clientIds = $documents->pluck('client_id')->unique();
        if ($clientIds->count() > 1) {
            return response()->json(['message' => 'All invoices must belong to the same client.'], 422);
        }

        // Block merge if any invoice has partial payments
        $hasPayments = $documents->filter(fn ($d) => (float) $d->paid_amount > 0);
        if ($hasPayments->count() > 0) {
            $nums = $hasPayments->pluck('document_number')->join(', ');
            return response()->json([
                'message' => "Cannot merge invoices with existing payments ({$nums}). Remove payments first.",
            ], 422);
        }

        return DB::transaction(function () use ($documents) {
            $client = $documents->first()->client;
            $tenant = auth()->user()->tenant;

            // Gather all line items and calculate totals
            $subtotal = 0;
            $discountTotal = 0;
            $taxAmount = 0;
            $allItems = [];
            $mergedNumbers = [];

            foreach ($documents as $doc) {
                $mergedNumbers[] = $doc->document_number;
                foreach ($doc->items as $item) {
                    $lineBase = $item->quantity * $item->price;
                    $lineDiscount = $item->discount_type === 'flat'
                        ? min($item->discount_value, $lineBase)
                        : $lineBase * ($item->discount_value / 100);

                    $subtotal += $lineBase;
                    $discountTotal += $lineDiscount;
                    $taxAmount += $item->tax_amount;

                    $allItems[] = [
                        'product_service_id' => $item->product_service_id,
                        'item_type' => $item->item_type,
                        'description' => $item->description,
                        'quantity' => $item->quantity,
                        'price' => $item->price,
                        'discount_type' => $item->discount_type,
                        'discount_value' => $item->discount_value,
                        'tax_percent' => $item->tax_percent,
                        'tax_amount' => $item->tax_amount,
                        'total' => $item->total,
                        'unit' => $item->unit,
                    ];
                }
            }

            // Use the latest due date from all merged invoices
            $latestDueDate = $documents->max('due_date');

            $mergedDoc = Document::create([
                'client_id' => $client->id,
                'type' => 'invoice',
                'document_number' => app(DocumentNumberService::class)
                    ->generate('invoice', $tenant->id),
                'date' => now()->format('Y-m-d'),
                'due_date' => $latestDueDate,
                'subtotal' => round($subtotal, 2),
                'discount_amount' => round($discountTotal, 2),
                'tax_amount' => round($taxAmount, 2),
                'total' => round($subtotal - $discountTotal + $taxAmount, 2),
                'notes' => 'Merged from: ' . implode(', ', $mergedNumbers),
                'status' => 'sent',
                'created_by' => auth()->id(),
            ]);

            foreach ($allItems as $item) {
                $mergedDoc->items()->create($item);
            }

            // Cancel original invoices
            foreach ($documents as $doc) {
                $doc->update(['status' => 'cancelled']);
            }

            // Send merged invoice to client
            $mergedDoc->load('items', 'client');
            $client->notify(new \App\Notifications\InvoiceSentNotification($mergedDoc));

            return response()->json([
                'data' => new DocumentResource($mergedDoc),
                'message' => "Merged " . count($mergedNumbers) . " invoices into {$mergedDoc->document_number}.",
            ]);
        });
    }

    public function remindUnpaid(Request $request)
    {
        $request->validate([
            'document_ids' => 'required|array|min:1',
            'document_ids.*' => 'uuid',
            'channel' => 'required|in:email,sms,whatsapp,both',
        ]);

        $tenant = Tenant::find(auth()->user()->tenant_id);
        $documents = Document::whereIn('id', $request->document_ids)
            ->where('type', 'invoice')
            ->whereNotIn('status', ['paid', 'draft', 'cancelled'])
            ->with('client')
            ->get();

        $sent = 0;
        $failed = 0;
        $skipped = 0;
        $errors = [];

        foreach ($documents as $document) {
            $client = $document->client;
            if (!$client) {
                $skipped++;
                continue;
            }

            // Need email or phone depending on channel
            if ($request->channel === 'email' && !$client->email) {
                $skipped++;
                continue;
            }
            if ($request->channel === 'sms' && !$client->phone) {
                $skipped++;
                continue;
            }

            $daysRemaining = $document->due_date
                ? (int) Carbon::today()->diffInDays($document->due_date, false)
                : 0;

            $notification = new RecurringInvoiceReminderNotification(
                $document,
                $tenant,
                max($daysRemaining, 0),
            );

            // Override channels based on user selection
            $notification->forceChannels = $request->channel;

            try {
                // Send immediately (not queued) for instant feedback
                $client->notifyNow($notification);
                $sent++;
            } catch (\Throwable $e) {
                $failed++;
                $errors[] = $client->name . ': ' . $e->getMessage();
            }
        }

        $message = "Reminder sent to {$sent} client(s)";
        if ($failed) {
            $message .= ", {$failed} failed";
        }
        if ($skipped) {
            $message .= ", {$skipped} skipped (missing contact)";
        }

        return response()->json([
            'message' => $message,
            'sent' => $sent,
            'failed' => $failed,
            'skipped' => $skipped,
            'errors' => $errors,
        ], $sent > 0 ? 200 : ($failed > 0 ? 422 : 200));
    }
}

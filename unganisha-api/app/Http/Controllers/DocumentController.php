<?php

namespace App\Http\Controllers;

use App\Http\Requests\StoreDocumentRequest;
use App\Http\Resources\DocumentResource;
use App\Models\CommunicationLog;
use App\Models\Document;
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
        $query = Document::with('client');

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

        $document->client->notify(new \App\Notifications\InvoiceSentNotification($document));
        $document->update(['status' => 'sent']);

        // Confirm to the sending user via in-app notification
        $request->user()->notify(new \App\Notifications\DocumentSentConfirmation($document));

        return response()->json(['message' => 'Document sent successfully']);
    }

    public function remindUnpaid(Request $request)
    {
        $request->validate([
            'document_ids' => 'required|array|min:1',
            'document_ids.*' => 'uuid',
            'channel' => 'required|in:email,sms,both',
        ]);

        $tenant = Tenant::find(auth()->user()->tenant_id);
        $documents = Document::whereIn('id', $request->document_ids)
            ->where('type', 'invoice')
            ->whereNotIn('status', ['paid', 'draft'])
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

<?php

namespace App\Http\Controllers;

use App\Http\Requests\StoreDocumentRequest;
use App\Http\Resources\DocumentResource;
use App\Models\Document;
use App\Services\DocumentConversionService;
use App\Services\DocumentNumberService;
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
            $query->where('status', $request->status);
        }

        if ($request->has('search')) {
            $search = $request->search;
            $query->where(function ($q) use ($search) {
                $q->where('document_number', 'LIKE', "%{$search}%")
                  ->orWhereHas('client', fn ($cq) => $cq->where('name', 'LIKE', "%{$search}%"));
            });
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
            $taxAmount = 0;

            foreach ($items as &$item) {
                $lineTotal = $item['quantity'] * $item['price'];
                $lineTax = $lineTotal * (($item['tax_percent'] ?? 0) / 100);
                $item['tax_amount'] = round($lineTax, 2);
                $item['total'] = round($lineTotal + $lineTax, 2);
                $subtotal += $lineTotal;
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
                'tax_amount' => round($taxAmount, 2),
                'total' => round($subtotal + $taxAmount, 2),
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
            $taxAmount = 0;

            foreach ($items as &$item) {
                $lineTotal = $item['quantity'] * $item['price'];
                $lineTax = $lineTotal * (($item['tax_percent'] ?? 0) / 100);
                $item['tax_amount'] = round($lineTax, 2);
                $item['total'] = round($lineTotal + $lineTax, 2);
                $subtotal += $lineTotal;
                $taxAmount += $lineTax;
            }

            $document->update([
                'client_id' => $request->client_id,
                'date' => $request->date,
                'due_date' => $request->due_date,
                'subtotal' => round($subtotal, 2),
                'tax_amount' => round($taxAmount, 2),
                'total' => round($subtotal + $taxAmount, 2),
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

        return response()->json(['message' => 'Document sent successfully']);
    }
}

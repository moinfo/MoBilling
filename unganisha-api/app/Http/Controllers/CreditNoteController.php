<?php

namespace App\Http\Controllers;

use App\Http\Requests\StoreCreditNoteRequest;
use App\Http\Resources\DocumentResource;
use App\Models\Client;
use App\Models\ClientCredit;
use App\Models\Document;
use App\Services\CreditService;
use App\Services\DocumentNumberService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Credit notes (WHMCS parity). A credit note formally credits a client: it reuses
 * the documents + document_items tables with type 'credit_note' and, on ISSUE,
 * deposits its total into the client's account credit wallet — exactly once.
 *
 * Status model (no new enum values): 'draft' = not yet issued, 'sent' = issued.
 */
class CreditNoteController extends Controller
{
    public function __construct(private CreditService $credit) {}

    public function index(Request $request)
    {
        $query = Document::where('type', 'credit_note')
            ->with(['client', 'items:id,document_id,description']);

        if ($request->filled('status')) {
            $query->where('status', $request->status);
        }

        if ($request->filled('client_id')) {
            $query->where('client_id', $request->client_id);
        }

        if ($request->filled('search')) {
            $search = $request->search;
            $query->where(function ($q) use ($search) {
                $q->where('document_number', 'LIKE', "%{$search}%")
                  ->orWhereHas('client', fn ($cq) => $cq->where('name', 'LIKE', "%{$search}%"));
            });
        }

        if ($request->filled('date_from')) {
            $query->where('date', '>=', $request->date_from);
        }
        if ($request->filled('date_to')) {
            $query->where('date', '<=', $request->date_to);
        }

        return DocumentResource::collection(
            $query->orderByDesc('created_at')->paginate($request->per_page ?? 20)
        );
    }

    public function show(Document $creditNote)
    {
        abort_unless($creditNote->type === 'credit_note', 404);

        return new DocumentResource($creditNote->load('items', 'client', 'parent'));
    }

    /**
     * Create a credit note (draft). Standalone, or "credit this invoice" when
     * source_invoice_id is supplied (links via parent_id). Wallet is NOT credited
     * here — that happens on issue().
     */
    public function store(StoreCreditNoteRequest $request)
    {
        $data = $request->validated();

        return DB::transaction(function () use ($data) {
            $items = $data['items'];
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
            unset($item);

            $sourceInvoiceId = null;
            if (!empty($data['source_invoice_id'])) {
                $source = Document::where('type', 'invoice')->find($data['source_invoice_id']);
                if ($source) {
                    $sourceInvoiceId = $source->id;
                }
            }

            $creditNote = Document::create([
                'client_id'       => $data['client_id'],
                'type'            => 'credit_note',
                'document_number' => app(DocumentNumberService::class)
                    ->generate('credit_note', auth()->user()->tenant_id),
                'parent_id'       => $sourceInvoiceId,
                'date'            => $data['date'] ?? now()->toDateString(),
                'subtotal'        => round($subtotal, 2),
                'discount_amount' => round($discountTotal, 2),
                'tax_amount'      => round($taxAmount, 2),
                'total'           => round($subtotal - $discountTotal + $taxAmount, 2),
                'notes'           => $data['notes'] ?? null,
                'status'          => 'draft',
                'created_by'      => auth()->id(),
            ]);

            foreach ($items as $item) {
                $creditNote->items()->create($item);
            }

            return new DocumentResource($creditNote->load('items', 'client'));
        });
    }

    /**
     * Issue the credit note: deposit its total into the client's wallet exactly
     * once, mark it 'sent' (issued), and optionally cancel the source invoice.
     * Double-issue is blocked by both the status guard and the existing-ledger check.
     */
    public function issue(Request $request, Document $creditNote)
    {
        abort_unless($creditNote->type === 'credit_note', 404);

        $result = DB::transaction(function () use ($request, $creditNote) {
            $cn = Document::whereKey($creditNote->id)->lockForUpdate()->first();

            if ($cn->status !== 'draft') {
                abort(422, 'This credit note has already been issued.');
            }

            // Belt-and-braces: never credit the wallet twice for the same credit note.
            $alreadyCredited = ClientCredit::withoutGlobalScopes()
                ->where('type', 'credit_note')
                ->where('document_id', $cn->id)
                ->exists();
            if ($alreadyCredited) {
                abort(422, 'This credit note has already credited the client.');
            }

            $total = (float) $cn->total;
            if ($total <= 0) {
                abort(422, 'A credit note must have a positive total to be issued.');
            }

            $client = Client::withoutGlobalScopes()->find($cn->client_id);
            $this->credit->adjust(
                $client, $total, 'credit_note',
                "Credit note {$cn->document_number}", $cn->id, auth()->id()
            );

            $cn->update(['status' => 'sent']);

            $sourceCancelled = false;
            if ($request->boolean('cancel_source_invoice') && $cn->parent_id) {
                $source = Document::whereKey($cn->parent_id)->where('type', 'invoice')->lockForUpdate()->first();
                // Only cancel an invoice with no payments recorded — cancelling one
                // with payments would orphan them in reports.
                if ($source && $source->status !== 'cancelled' && (float) $source->paid_amount <= 0) {
                    $source->update(['status' => 'cancelled']);
                    $sourceCancelled = true;
                }
            }

            return ['cn' => $cn, 'sourceCancelled' => $sourceCancelled];
        });

        $message = "Credit note {$creditNote->document_number} issued — "
            . number_format((float) $result['cn']->total, 2) . ' credited to the client.';
        if ($result['sourceCancelled']) {
            $message .= ' Source invoice cancelled.';
        }

        return response()->json([
            'data'    => new DocumentResource($result['cn']->fresh()->load('items', 'client')),
            'message' => $message,
        ]);
    }

    public function destroy(Document $creditNote)
    {
        abort_unless($creditNote->type === 'credit_note', 404);

        if ($creditNote->status !== 'draft') {
            return response()->json([
                'message' => 'Only a draft (un-issued) credit note can be deleted.',
            ], 422);
        }

        $creditNote->items()->delete();
        $creditNote->delete();

        return response()->json(['message' => 'Credit note deleted.']);
    }

    public function downloadPdf(Document $creditNote)
    {
        abort_unless($creditNote->type === 'credit_note', 404);

        $creditNote->load('items', 'client', 'tenant');
        $pdf = app(\App\Services\PdfService::class)->generate($creditNote);

        return $pdf->download("{$creditNote->document_number}.pdf");
    }
}

<?php

namespace App\Http\Controllers;

use App\Http\Requests\StoreRefundRequest;
use App\Models\Client;
use App\Models\Document;
use App\Models\Refund;
use App\Services\CreditService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class RefundController extends Controller
{
    public function __construct(private CreditService $credit) {}

    /** List refunds, optionally scoped to a single invoice (?document_id=). */
    public function index(Request $request)
    {
        $query = Refund::with(['document:id,document_number', 'client:id,name', 'refundedBy:id,name']);

        if ($request->filled('document_id')) {
            $query->where('document_id', $request->document_id);
        }

        return response()->json([
            'data' => $query->orderByDesc('created_at')
                ->paginate($request->per_page ?? 50)
                ->through(fn ($r) => $this->serialize($r)),
        ]);
    }

    /**
     * Refund money already paid on an invoice. In one transaction: guard the
     * amount against the current (net) paid amount, record the refund, credit
     * the wallet if method=wallet, and recompute the invoice status from the
     * now-reduced paid_amount (same rules as PaymentInController).
     */
    public function store(StoreRefundRequest $request, Document $invoice)
    {
        abort_unless($invoice->type === 'invoice', 422, 'Refunds can only be recorded against invoices.');

        $amount = round((float) $request->validated()['amount'], 2);

        $result = DB::transaction(function () use ($request, $invoice, $amount) {
            $document = Document::whereKey($invoice->id)->lockForUpdate()->first();

            $paidAmount = (float) $document->paid_amount; // net of prior refunds

            if ($paidAmount <= 0) {
                abort(422, 'This invoice has no payment to refund.');
            }

            if ($amount > $paidAmount + 0.001) {
                abort(422, 'Refund amount cannot exceed the amount paid ('
                    . number_format($paidAmount, 2) . ').');
            }

            $refund = Refund::create([
                'document_id' => $document->id,
                'client_id'   => $document->client_id,
                'amount'      => $amount,
                'method'      => $request->validated()['method'],
                'reference'   => $request->validated()['reference'] ?? null,
                'notes'       => $request->validated()['reason'] ?? null,
                'refunded_by' => auth()->id(),
            ]);

            // Wallet refunds add reusable account credit; external refunds
            // (cash/bank/mobile money) are audit records only.
            if ($request->validated()['method'] === 'wallet') {
                $client = Client::withoutGlobalScopes()->find($document->client_id);
                $this->credit->adjust(
                    $client, $amount, 'refund',
                    "Refund for {$document->document_number}", $document->id, auth()->id()
                );
            }

            $this->recalcStatus($document);

            return $refund;
        });

        return response()->json([
            'data'    => $this->serialize($result->fresh(['document:id,document_number', 'client:id,name'])),
            'invoice' => new \App\Http\Resources\DocumentResource(
                Document::whereKey($invoice->id)->with(['items', 'client', 'payments'])->first()
            ),
            'message' => 'Refund of ' . number_format($amount, 2) . ' recorded for ' . $invoice->document_number . '.',
        ], 201);
    }

    /**
     * Recompute the invoice status from the net paid_amount — mirrors
     * PaymentInController::recalcDocumentStatus so a refund correctly reverts a
     * paid invoice to partial/sent.
     */
    private function recalcStatus(Document $document): void
    {
        $paid = (float) $document->paid_amount;

        if ($paid >= (float) $document->total && $paid > 0) {
            $document->update(['status' => 'paid']);
        } elseif ($paid > 0) {
            $document->update(['status' => 'partial']);
        } else {
            $document->update(['status' => 'sent']);
        }
    }

    private function serialize(Refund $r): array
    {
        return [
            'id'              => $r->id,
            'document_id'     => $r->document_id,
            'document_number' => $r->document?->document_number,
            'client_id'       => $r->client_id,
            'client_name'     => $r->client?->name,
            'amount'          => (float) $r->amount,
            'method'          => $r->method,
            'reference'       => $r->reference,
            'notes'           => $r->notes,
            'refunded_by'     => $r->refundedBy?->name,
            'created_at'      => $r->created_at?->toISOString(),
        ];
    }
}

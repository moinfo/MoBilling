<?php

namespace App\Http\Controllers;

use App\Models\Client;
use App\Models\ClientCredit;
use App\Models\Document;
use App\Services\CreditService;
use Illuminate\Http\Request;

class ClientCreditController extends Controller
{
    public function __construct(private CreditService $credit) {}

    /** Balance + ledger for a client. */
    public function show(Client $client)
    {
        return response()->json(['data' => [
            'balance' => (float) $client->credit_balance,
            'ledger'  => ClientCredit::where('client_id', $client->id)
                ->where('type', '!=', 'topup_pending')
                ->orderByDesc('created_at')->limit(50)
                ->get()
                ->map(fn ($c) => [
                    'id'            => $c->id,
                    'type'          => $c->type,
                    'amount'        => (float) $c->amount,
                    'balance_after' => (float) ($c->balance_after ?? 0),
                    'notes'         => $c->notes,
                    'created_at'    => $c->created_at->toISOString(),
                ]),
        ]]);
    }

    /** Staff: add or remove credit manually. */
    public function adjust(Request $request, Client $client)
    {
        $data = $request->validate([
            'amount' => 'required|numeric|not_in:0',
            'notes'  => 'required|string|max:255',
        ]);

        try {
            $balance = $this->credit->adjust($client, (float) $data['amount'], 'adjustment', $data['notes'], null, auth()->id());
        } catch (\RuntimeException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return response()->json([
            'data'    => ['balance' => $balance],
            'message' => 'Credit ' . ($data['amount'] > 0 ? 'added' : 'removed') . ' — new balance: ' . number_format($balance, 2),
        ]);
    }

    /** Staff: apply the client's credit to one of their unpaid invoices. */
    public function applyToInvoice(Request $request, Document $document)
    {
        abort_unless($document->type === 'invoice', 422, 'Credit can only be applied to invoices.');

        $client = Client::find($document->client_id);
        abort_unless($client, 404);

        try {
            $payment = $this->credit->applyToInvoice($client, $document, null, auth()->id());
        } catch (\RuntimeException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return response()->json([
            'message' => 'Applied ' . number_format((float) $payment->amount, 2) . ' credit to ' . $document->document_number . '.',
        ]);
    }
}

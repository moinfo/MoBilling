<?php

namespace App\Http\Controllers\Portal;

use App\Http\Controllers\Controller;
use App\Models\Client;
use App\Models\ClientCredit;
use App\Models\Document;
use App\Services\CreditService;
use App\Services\DocumentNumberService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class PortalCreditController extends Controller
{
    /** The client's wallet: balance + recent ledger. */
    public function show(Request $request)
    {
        $client = Client::find($request->user()->client_id);

        return response()->json(['data' => [
            'balance' => (float) ($client?->credit_balance ?? 0),
            'ledger'  => ClientCredit::where('client_id', $client?->id)
                ->where('type', '!=', 'topup_pending')
                ->orderByDesc('created_at')->limit(30)
                ->get()
                ->map(fn ($c) => [
                    'id'         => $c->id,
                    'type'       => $c->type,
                    'amount'     => (float) $c->amount,
                    'notes'      => $c->notes,
                    'created_at' => $c->created_at->toISOString(),
                ]),
        ]]);
    }

    /** Add Funds: invoice now, credit deposited automatically when paid. */
    public function topup(Request $request)
    {
        $user = $request->user();

        $data = $request->validate([
            'amount' => 'required|numeric|min:5000|max:10000000',
        ]);
        $amount = round((float) $data['amount'], 2);

        $document = DB::transaction(function () use ($user, $amount) {
            $document = Document::withoutGlobalScopes()->create([
                'tenant_id'       => $user->tenant_id,
                'client_id'       => $user->client_id,
                'type'            => 'invoice',
                'document_number' => app(DocumentNumberService::class)->generate('invoice', $user->tenant_id),
                'date'            => now()->toDateString(),
                'due_date'        => now()->toDateString(),
                'subtotal'        => $amount,
                'discount_amount' => 0,
                'tax_amount'      => 0,
                'total'           => $amount,
                'status'          => 'sent',
                'notes'           => 'Add funds — account credit top-up',
            ]);

            $document->items()->create([
                'item_type'   => 'service',
                'description' => 'Account credit top-up',
                'quantity'    => 1,
                'price'       => $amount,
                'tax_percent' => 0,
                'tax_amount'  => 0,
                'total'       => $amount,
            ]);

            ClientCredit::withoutGlobalScopes()->create([
                'tenant_id'   => $user->tenant_id,
                'client_id'   => $user->client_id,
                'type'        => 'topup_pending',
                'amount'      => $amount,
                'document_id' => $document->id,
                'notes'       => 'Awaiting payment',
            ]);

            return $document;
        });

        return response()->json([
            'data'    => ['document_id' => $document->id, 'document_number' => $document->document_number, 'total' => $amount],
            'message' => "Invoice {$document->document_number} created — your credit is added the moment it is paid.",
        ], 201);
    }

    /** Apply credit to one of the client's own unpaid invoices (portal admins). */
    public function applyToInvoice(Request $request, Document $document, CreditService $credit)
    {
        $user = $request->user();
        abort_unless($document->client_id === $user->client_id, 404);
        abort_unless($user->role === 'admin', 403, 'Only portal administrators can apply credit.');
        abort_unless($document->type === 'invoice', 422);

        // Never let credit pay for its own top-up invoice.
        $isTopup = ClientCredit::withoutGlobalScopes()
            ->whereIn('type', ['topup_pending', 'topup_consumed'])
            ->where('document_id', $document->id)->exists();
        abort_if($isTopup, 422, 'Top-up invoices cannot be paid with credit.');

        $client = Client::find($user->client_id);

        try {
            $payment = $credit->applyToInvoice($client, $document);
        } catch (\RuntimeException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return response()->json([
            'message' => 'Applied Tsh.' . number_format((float) $payment->amount, 2) . ' credit to ' . $document->document_number . '.',
        ]);
    }
}

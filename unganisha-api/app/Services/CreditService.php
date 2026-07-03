<?php

namespace App\Services;

use App\Models\Client;
use App\Models\ClientCredit;
use App\Models\Document;
use App\Models\PaymentIn;
use Illuminate\Support\Facades\DB;

/**
 * Client credit wallet. Every mutation locks the client row and writes a
 * ledger entry with the running balance — the ledger is the audit trail,
 * clients.credit_balance is the cached authoritative balance.
 */
class CreditService
{
    /** Add (or with negative amount, remove) credit. Returns the new balance. */
    public function adjust(Client $client, float $amount, string $type = 'adjustment', ?string $notes = null, ?string $documentId = null, ?string $byUserId = null): float
    {
        return DB::transaction(function () use ($client, $amount, $type, $notes, $documentId, $byUserId) {
            $locked = Client::withoutGlobalScopes()->whereKey($client->id)->lockForUpdate()->first();
            $newBalance = round((float) $locked->credit_balance + $amount, 2);

            if ($newBalance < 0) {
                throw new \RuntimeException('Insufficient credit balance.');
            }

            $locked->update(['credit_balance' => $newBalance]);

            ClientCredit::withoutGlobalScopes()->create([
                'tenant_id'     => $locked->tenant_id,
                'client_id'     => $locked->id,
                'type'          => $type,
                'amount'        => $amount,
                'balance_after' => $newBalance,
                'document_id'   => $documentId,
                'created_by'    => $byUserId,
                'notes'         => $notes,
            ]);

            return $newBalance;
        });
    }

    /**
     * Apply available credit to an unpaid invoice: spends min(balance, due),
     * recorded as a PaymentIn (method 'credit') so the normal payment flow —
     * status recompute, activation, fulfilment — runs unchanged.
     */
    public function applyToInvoice(Client $client, Document $document, ?float $amount = null, ?string $byUserId = null): PaymentIn
    {
        return DB::transaction(function () use ($client, $document, $amount, $byUserId) {
            $locked = Client::withoutGlobalScopes()->whereKey($client->id)->lockForUpdate()->first();
            $doc    = Document::withoutGlobalScopes()->whereKey($document->id)->lockForUpdate()->first();

            $due = (float) $doc->total - (float) $doc->payments()->sum('amount');
            if ($due <= 0) {
                throw new \RuntimeException('This invoice has no outstanding balance.');
            }

            $spend = round(min((float) $locked->credit_balance, $due, $amount ?? INF), 2);
            if ($spend <= 0) {
                throw new \RuntimeException('No credit available to apply.');
            }

            $newBalance = round((float) $locked->credit_balance - $spend, 2);
            $locked->update(['credit_balance' => $newBalance]);

            ClientCredit::withoutGlobalScopes()->create([
                'tenant_id'     => $locked->tenant_id,
                'client_id'     => $locked->id,
                'type'          => 'apply',
                'amount'        => -$spend,
                'balance_after' => $newBalance,
                'document_id'   => $doc->id,
                'created_by'    => $byUserId,
                'notes'         => "Applied to {$doc->document_number}",
            ]);

            $payment = PaymentIn::withoutGlobalScopes()->create([
                'tenant_id'      => $locked->tenant_id,
                'client_id'      => $locked->id,
                'document_id'    => $doc->id,
                'amount'         => $spend,
                'payment_date'   => now()->toDateString(),
                'payment_method' => 'credit',
                'notes'          => 'Account credit applied',
                'received_by'    => $byUserId,
            ]);

            // Recompute invoice status (mirrors PaymentInController::recalc).
            $totalPaid = $doc->payments()->sum('amount');
            if ($totalPaid >= (float) $doc->total) {
                $doc->update(['status' => 'paid']);
                app(SubscriptionActivationService::class)->activateFor($doc);
            } else {
                $doc->update(['status' => 'partial']);
            }

            return $payment;
        });
    }
}

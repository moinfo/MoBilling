<?php

namespace App\Services;

use App\Models\Client;
use App\Models\Document;
use App\Models\PaymentIn;
use App\Models\Tenant;
use App\Models\User;
use App\Notifications\PaymentReceiptNotification;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;

/**
 * Staff recording of offline payments (bank transfer / mobile money / lipa namba) against unpaid invoices,
 * single or split across several invoices of one client. Mirrors PaymentInController::store (transaction +
 * lockForUpdate + status recompute + subscription activation + receipt outside the transaction) and adds
 * duplicate guards, an idempotency key, client credit for excess and an undo window.
 */
class OfflinePaymentService
{
    public const UNPAID = ['sent', 'overdue', 'partial'];
    public const DUP_DAYS = 90;
    public const RECENT_MINUTES = 10;
    public const UNDO_MINUTES = 15;
    private const HIDDEN_METHODS = ['pesapal', 'credit', 'card'];
    private const NO_REF_METHODS = ['cash', 'cheque', 'other'];

    /** [{value,label,reference_required}] — the tenant's configured methods minus online/internal ones. */
    public static function methodsFor(?Tenant $tenant): array
    {
        $configured = collect($tenant?->payment_methods ?? [])->filter(fn ($m) => !empty($m['value']));
        if ($configured->isEmpty()) {
            $configured = collect([['value' => 'bank', 'label' => 'Bank Transfer'], ['value' => 'mpesa', 'label' => 'Mobile Money / Lipa Namba']]);
        }

        return $configured
            ->reject(fn ($m) => in_array(strtolower($m['value']), self::HIDDEN_METHODS, true))
            ->map(fn ($m) => [
                'value' => $m['value'],
                'label' => $m['label'] ?? $m['value'],
                'reference_required' => !in_array(strtolower($m['value']), self::NO_REF_METHODS, true),
            ])->values()->all();
    }

    public static function normRef(?string $ref): string
    {
        return mb_strtolower(trim((string) $ref));
    }

    /** SQL fragment: invoice balance (total - payments + refunds). Table alias is `documents`. */
    public static function balanceSql(): string
    {
        return 'documents.total - COALESCE((select sum(p.amount) from payments_in p where p.document_id = documents.id), 0)'
            . ' + COALESCE((select sum(r.amount) from refunds r where r.document_id = documents.id), 0)';
    }

    /**
     * @param string[] $invoiceIds
     * @param array $in method, payment_date, reference, notes, send_receipt, allow_excess, confirm_different, idempotency_key
     * @return array ['payments'=>PaymentIn[], 'invoices'=>[...], 'excess_credit'=>float, 'replayed'=>bool]
     * @throws OfflinePaymentException
     */
    public function record(User $user, array $invoiceIds, float $amount, array $in, ?UploadedFile $proof = null): array
    {
        $tenantId = $user->tenant_id;
        $tenant = $user->tenant;
        $invoiceIds = array_values(array_unique($invoiceIds));
        $amount = round($amount, 2);
        $method = (string) ($in['method'] ?? '');
        $reference = trim((string) ($in['reference'] ?? '')) ?: null;
        $date = $in['payment_date'] ?? now()->toDateString();

        // ── validation that needs no locks
        $methods = collect(self::methodsFor($tenant))->keyBy('value');
        if (!$methods->has($method)) {
            throw new OfflinePaymentException('That payment method is not available for recording offline payments.', 422, 'invalid_method');
        }
        if ($methods[$method]['reference_required'] && !$reference) {
            throw new OfflinePaymentException('A reference / transaction ID is required for this payment method.', 422, 'reference_required');
        }
        if ($amount <= 0) {
            throw new OfflinePaymentException('Amount must be greater than zero.', 422, 'invalid_amount');
        }
        if (strtotime($date) === false || $date > now()->toDateString()) {
            throw new OfflinePaymentException('Payment date cannot be in the future.', 422, 'invalid_date');
        }
        if (empty($invoiceIds)) {
            throw new OfflinePaymentException('Select at least one invoice.', 422, 'no_invoices');
        }
        if ($proof) {
            $this->validateProof($proof);
        }

        $idemKey = !empty($in['idempotency_key']) ? "offpay:idem:{$tenantId}:{$user->id}:" . md5($in['idempotency_key']) : null;
        $locks = [];
        try {
            if ($idemKey) {
                $locks[] = $l = Cache::lock($idemKey . ':lock', 30);
                $l->block(10);
                if ($hit = Cache::get($idemKey)) {
                    return $this->rehydrate($hit);
                }
            }
            if ($reference) {
                // serialises two staff pasting the same SMS at once
                $locks[] = $l = Cache::lock("offpay:ref:{$tenantId}:" . md5($method . '|' . self::normRef($reference)), 30);
                $l->block(10);
            }

            $storedPath = null;
            try {
                $result = DB::transaction(function () use ($user, $tenantId, $invoiceIds, $amount, $in, $method, $reference, $date, $proof, &$storedPath) {
                    $docs = Document::withoutGlobalScopes()->where('tenant_id', $tenantId)->whereIn('id', $invoiceIds)
                        ->orderBy('due_date')->orderBy('date')->orderBy('created_at')->lockForUpdate()->get();
                    if ($docs->count() !== count($invoiceIds)) {
                        throw new OfflinePaymentException('Invoice not found.', 404, 'not_found');
                    }
                    if ($docs->pluck('client_id')->unique()->count() > 1) {
                        throw new OfflinePaymentException('A split payment must be for invoices of the same client.', 422, 'mixed_clients');
                    }
                    // nulls last for due_date (MySQL sorts NULL first)
                    $docs = $docs->sortBy(fn ($d) => [$d->due_date ? 0 : 1, (string) $d->due_date, (string) $d->date, (string) $d->created_at])->values();
                    foreach ($docs as $d) {
                        if ($d->type !== 'invoice' || !in_array($d->status, self::UNPAID, true)) {
                            throw new OfflinePaymentException("Invoice {$d->document_number} is {$d->status} and cannot receive a payment.", 409, 'invoice_not_payable', ['document_number' => $d->document_number, 'status' => $d->status]);
                        }
                    }

                    // ── allocate oldest-first against balances (net of refunds)
                    $remaining = $amount;
                    $alloc = [];
                    foreach ($docs as $d) {
                        $bal = round((float) $d->total - $this->paidNet($d), 2);
                        if ($bal <= 0) {
                            throw new OfflinePaymentException("Invoice {$d->document_number} has no outstanding balance.", 409, 'invoice_not_payable');
                        }
                        $take = round(min($remaining, $bal), 2);
                        if ($take > 0) {
                            $alloc[] = [$d, $take, $bal];
                            $remaining = round($remaining - $take, 2);
                        }
                    }
                    $excess = $remaining;
                    if ($excess > 0 && empty($in['allow_excess'])) {
                        throw new OfflinePaymentException('The amount is more than the balance due. Reduce it or tick "record excess as client credit".', 422, 'exceeds_balance', ['excess' => $excess]);
                    }

                    // ── duplicate guards (override with confirm_different)
                    if (empty($in['confirm_different'])) {
                        if ($reference) {
                            $dup = PaymentIn::withoutGlobalScopes()->where('tenant_id', $tenantId)
                                ->where('payment_method', $method)
                                ->whereRaw('LOWER(TRIM(reference)) = ?', [self::normRef($reference)])
                                ->where('created_at', '>=', now()->subDays(self::DUP_DAYS))->latest('created_at')->first();
                            if ($dup) {
                                $dd = Document::withoutGlobalScopes()->find($dup->document_id);
                                throw new OfflinePaymentException('This reference was already recorded' . ($dd ? " against {$dd->document_number}" : '') . ' on ' . $dup->payment_date->format('d M Y') . '. It may be the same payment.', 409, 'duplicate_reference', [
                                    'existing' => ['amount' => (float) $dup->amount, 'payment_date' => $dup->payment_date->format('Y-m-d'), 'document_number' => $dd?->document_number],
                                ]);
                            }
                        }
                        foreach ($alloc as [$d, $take]) {
                            $recent = PaymentIn::withoutGlobalScopes()->where('tenant_id', $tenantId)->where('document_id', $d->id)
                                ->where('amount', $take)->where('created_at', '>=', now()->subMinutes(self::RECENT_MINUTES))->exists();
                            if ($recent) {
                                throw new OfflinePaymentException("A payment of the same amount was recorded for {$d->document_number} in the last " . self::RECENT_MINUTES . ' minutes. Confirm it is a different payment.', 409, 'recent_same_amount', ['document_number' => $d->document_number]);
                            }
                        }
                    }

                    $path = null;
                    if ($proof) {
                        $path = $proof->store("payment-proofs/{$tenantId}", 'local');
                        $storedPath = $path;
                    }

                    $split = count($alloc) > 1;
                    $payments = [];
                    $summary = [];
                    foreach ($alloc as [$d, $take, $bal]) {
                        $notes = trim(($in['notes'] ?? '') . ($split ? " [split from ref {$reference}]" : ''));
                        $payment = PaymentIn::withoutGlobalScopes()->create([
                            'tenant_id' => $tenantId, 'client_id' => $d->client_id, 'document_id' => $d->id,
                            'amount' => $take, 'payment_date' => $date, 'payment_method' => $method,
                            'reference' => $reference, 'notes' => $notes ?: null, 'attachment_path' => $path,
                            'received_by' => $user->id,
                        ]);
                        $status = $this->recalc($d);
                        $payments[] = $payment;
                        $summary[] = ['document_id' => $d->id, 'document_number' => $d->document_number, 'amount' => $take,
                            'balance_after' => round($bal - $take, 2), 'status' => $status, 'payment_id' => $payment->id];
                    }

                    if ($excess > 0) {
                        $client = Client::withoutGlobalScopes()->where('tenant_id', $tenantId)->findOrFail($docs->first()->client_id);
                        app(CreditService::class)->adjust($client, $excess, 'deposit',
                            "Excess of {$method} payment " . ($reference ?: '') . " [receive-payments:{$payments[0]->id}]", $docs->first()->id, $user->id);
                    }

                    return ['payments' => $payments, 'invoices' => $summary, 'excess_credit' => $excess];
                });
            } catch (\Throwable $e) {
                if ($storedPath) {
                    try { Storage::disk('local')->delete($storedPath); } catch (\Throwable $x) { /* best effort */ }
                }
                throw $e;
            }

            // receipts: outside the transaction, network I/O must not hold row locks
            if (($in['send_receipt'] ?? true)) {
                foreach ($result['payments'] as $p) {
                    try {
                        $doc = Document::withoutGlobalScopes()->with('client')->find($p->document_id);
                        if ($doc?->client && ($doc->client->email || $doc->client->phone)) {
                            $doc->client->notify(new PaymentReceiptNotification($p, $doc));
                        }
                    } catch (\Throwable $e) {
                        report($e);
                    }
                }
            }

            $result['replayed'] = false;
            if ($idemKey) {
                Cache::put($idemKey, ['payment_ids' => collect($result['payments'])->pluck('id')->all(), 'invoices' => $result['invoices'], 'excess_credit' => $result['excess_credit']], now()->addMinutes(10));
            }

            return $result;
        } finally {
            foreach ($locks as $l) {
                try { $l->release(); } catch (\Throwable $e) { /* expired */ }
            }
        }
    }

    /** Undo one payment recorded by this user in the last 15 minutes (same effect as PaymentInController::destroy). */
    public function undo(User $user, string $paymentId): Document
    {
        return DB::transaction(function () use ($user, $paymentId) {
            $p = PaymentIn::withoutGlobalScopes()->where('tenant_id', $user->tenant_id)->whereKey($paymentId)->lockForUpdate()->first();
            if (!$p) {
                throw new OfflinePaymentException('Payment not found.', 404, 'not_found');
            }
            if ($p->received_by !== $user->id || $p->created_at->lt(now()->subMinutes(self::UNDO_MINUTES))) {
                throw new OfflinePaymentException('Only your own payments can be undone, within ' . self::UNDO_MINUTES . ' minutes of recording.', 403, 'undo_window');
            }
            if (\App\Models\ClientCredit::withoutGlobalScopes()->where('tenant_id', $user->tenant_id)->where('notes', 'like', "%[receive-payments:{$p->id}]%")->exists()) {
                throw new OfflinePaymentException('This payment also created client credit; reverse that from the client credit page instead.', 422, 'has_credit');
            }
            $doc = Document::withoutGlobalScopes()->whereKey($p->document_id)->lockForUpdate()->first();
            $path = $p->attachment_path;
            $p->delete();
            if ($doc) {
                $paid = $this->paidNet($doc);
                $doc->update(['status' => $paid >= (float) $doc->total ? 'paid' : ($paid > 0 ? 'partial' : ($doc->due_date && $doc->due_date->lt(now()->startOfDay()) ? 'overdue' : 'sent'))]);
            }
            // keep the proof if a split sibling still uses it
            if ($path && !PaymentIn::withoutGlobalScopes()->where('attachment_path', $path)->exists()) {
                try { Storage::disk('local')->delete($path); } catch (\Throwable $e) { /* best effort */ }
            }

            return $doc;
        });
    }

    private function paidNet(Document $d): float
    {
        return round((float) PaymentIn::withoutGlobalScopes()->where('document_id', $d->id)->sum('amount')
            - (float) \App\Models\Refund::withoutGlobalScopes()->where('document_id', $d->id)->sum('amount'), 2);
    }

    /** Same rule as PaymentInController::store. */
    private function recalc(Document $d): string
    {
        if ($this->paidNet($d) >= (float) $d->total) {
            $d->update(['status' => 'paid']);
            app(SubscriptionActivationService::class)->activateFor($d);

            return 'paid';
        }
        $d->update(['status' => 'partial']);

        return 'partial';
    }

    private function validateProof(UploadedFile $f): void
    {
        $mime = $f->getMimeType();
        $ext = strtolower($f->getClientOriginalExtension());
        if (!$f->isValid() || $f->getSize() > 5 * 1024 * 1024
            || !in_array($mime, ['image/jpeg', 'image/png', 'image/webp', 'application/pdf'], true)
            || !in_array($ext, ['jpg', 'jpeg', 'png', 'webp', 'pdf'], true)) {
            throw new OfflinePaymentException('Proof must be an image (JPG/PNG/WEBP) or PDF of at most 5 MB.', 422, 'invalid_proof');
        }
    }

    private function rehydrate(array $hit): array
    {
        return [
            'payments' => PaymentIn::withoutGlobalScopes()->whereIn('id', $hit['payment_ids'])->get()->all(),
            'invoices' => $hit['invoices'], 'excess_credit' => $hit['excess_credit'], 'replayed' => true,
        ];
    }
}

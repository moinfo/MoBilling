<?php

namespace App\Services;

use App\Models\Tenant;
use App\Models\TenantWalletTransaction;
use Illuminate\Support\Facades\DB;

/**
 * A white-label reseller tenant's prepaid wallet — the tenant-level analog
 * of CreditService (client credit). Every mutation locks the tenant row and
 * writes a ledger entry with the running balance; tenants.wallet_balance is
 * the cached authoritative balance. Used only for tenants provisioned from
 * a ResellerApplication (Tenant::is_wallet_gated) — see
 * TenantWalletGateService for the fulfillment-side debit.
 */
class TenantWalletService
{
    public function balance(Tenant $tenant): float
    {
        return (float) Tenant::withoutGlobalScopes()->whereKey($tenant->id)->value('wallet_balance');
    }

    /**
     * Add funds. $relatedType/$relatedId let a topup trace back to its
     * source (e.g. a PesapalInvoicePayment-style purchase row).
     */
    public function topUp(Tenant $tenant, float $amount, ?string $reference = null, ?string $notes = null, ?string $byUserId = null, ?string $relatedType = null, ?string $relatedId = null): float
    {
        if ($amount <= 0) {
            throw new \InvalidArgumentException('Top-up amount must be greater than zero.');
        }

        $newBalance = DB::transaction(function () use ($tenant, $amount, $reference, $notes, $byUserId, $relatedType, $relatedId) {
            $locked = Tenant::withoutGlobalScopes()->whereKey($tenant->id)->lockForUpdate()->first();
            $newBalance = round((float) $locked->wallet_balance + $amount, 2);
            $locked->update(['wallet_balance' => $newBalance]);

            TenantWalletTransaction::withoutGlobalScopes()->create([
                'tenant_id'     => $locked->id,
                'type'          => 'topup',
                'amount'        => $amount,
                'balance_after' => $newBalance,
                'reference'     => $reference,
                'related_type'  => $relatedType,
                'related_id'    => $relatedId,
                'created_by'    => $byUserId,
                'notes'         => $notes,
            ]);

            return $newBalance;
        });

        // Fulfil anything that was held for lack of balance — as far as the
        // refreshed balance now covers, oldest first.
        try {
            app(TenantWalletGateService::class)->retryHeld($tenant->fresh());
        } catch (\Throwable $e) {
            report($e);
        }

        return $newBalance;
    }

    /**
     * Debit at cost. Idempotent per ($relatedType, $relatedId, $reference):
     * if a debit with the same reference already exists for this related
     * record, returns false (already charged) instead of debiting again.
     * Returns true on a fresh debit, false if insufficient balance OR
     * already debited (check via alreadyDebited() first when the caller
     * needs to distinguish).
     */
    public function debit(Tenant $tenant, float $amount, string $relatedType, string $relatedId, ?string $reference = null, ?string $notes = null): bool
    {
        if ($amount <= 0) {
            return true; // nothing to charge
        }

        return DB::transaction(function () use ($tenant, $amount, $relatedType, $relatedId, $reference, $notes) {
            if ($this->alreadyDebited($relatedType, $relatedId)) {
                return true; // idempotent replay — already charged, treat as success
            }

            $locked = Tenant::withoutGlobalScopes()->whereKey($tenant->id)->lockForUpdate()->first();
            $current = (float) $locked->wallet_balance;
            if (round($current - $amount, 2) < 0) {
                return false; // insufficient — caller holds fulfillment
            }

            $newBalance = round($current - $amount, 2);
            $locked->update(['wallet_balance' => $newBalance]);

            TenantWalletTransaction::withoutGlobalScopes()->create([
                'tenant_id'     => $locked->id,
                'type'          => 'debit',
                'amount'        => -$amount,
                'balance_after' => $newBalance,
                'reference'     => $reference,
                'related_type'  => $relatedType,
                'related_id'    => $relatedId,
                'notes'         => $notes,
            ]);

            return true;
        });
    }

    /** True if a debit ledger row already exists for this related record (idempotency guard). */
    public function alreadyDebited(string $relatedType, string $relatedId): bool
    {
        return TenantWalletTransaction::withoutGlobalScopes()
            ->where('related_type', $relatedType)->where('related_id', $relatedId)
            ->where('type', 'debit')->exists();
    }

    public function refund(Tenant $tenant, float $amount, string $relatedType, string $relatedId, ?string $notes = null, ?string $byUserId = null): float
    {
        return DB::transaction(function () use ($tenant, $amount, $relatedType, $relatedId, $notes, $byUserId) {
            $locked = Tenant::withoutGlobalScopes()->whereKey($tenant->id)->lockForUpdate()->first();
            $newBalance = round((float) $locked->wallet_balance + $amount, 2);
            $locked->update(['wallet_balance' => $newBalance]);

            TenantWalletTransaction::withoutGlobalScopes()->create([
                'tenant_id'     => $locked->id,
                'type'          => 'refund',
                'amount'        => $amount,
                'balance_after' => $newBalance,
                'related_type'  => $relatedType,
                'related_id'    => $relatedId,
                'created_by'    => $byUserId,
                'notes'         => $notes,
            ]);

            return $newBalance;
        });
    }
}

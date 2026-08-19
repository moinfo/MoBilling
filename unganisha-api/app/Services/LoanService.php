<?php

namespace App\Services;

use App\Models\Loan;
use App\Models\LoanPayment;
use Illuminate\Support\Facades\DB;

/**
 * Loan balance ledger — mirrors CreditService: every mutation locks the
 * loan row and writes an immutable ledger entry with the running balance.
 * loans.balance is the cached authoritative figure.
 */
class LoanService
{
    /** Record a repayment, decrementing balance (clamped at 0). Returns the LoanPayment row. */
    public function recordPayment(Loan $loan, float $amount, ?string $payrollRunId = null, ?string $byUserId = null, ?string $notes = null): LoanPayment
    {
        return DB::transaction(function () use ($loan, $amount, $payrollRunId, $byUserId, $notes) {
            $locked = Loan::withoutGlobalScopes()->whereKey($loan->id)->lockForUpdate()->first();
            $newBalance = round(max(0, (float) $locked->balance - $amount), 2);

            $locked->update([
                'balance' => $newBalance,
                'status' => $newBalance <= 0 ? 'paid_off' : $locked->status,
            ]);

            return LoanPayment::withoutGlobalScopes()->create([
                'tenant_id' => $locked->tenant_id,
                'loan_id' => $locked->id,
                'payroll_run_id' => $payrollRunId,
                'amount' => $amount,
                'balance_after' => $newBalance,
                'created_by' => $byUserId,
                'notes' => $notes,
            ]);
        });
    }
}

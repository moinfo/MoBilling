<?php

namespace App\Http\Controllers;

use App\Models\Expense;
use App\Models\PettyCashAccount;
use App\Models\PettyCashReconciliation;
use App\Models\PettyCashTransaction;
use App\Services\PdfService;
use Illuminate\Database\QueryException;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\ValidationException;

class PettyCashController extends Controller
{
    /**
     * Return the account, current balance, a unified history (top-ups,
     * returns, adjustments, expenses), and recent reconciliations.
     */
    public function index(Request $request)
    {
        $account = $this->getOrCreateAccount();

        $balance = $this->computeBalance($account);

        $transactions = PettyCashTransaction::where('petty_cash_account_id', $account->id)
            ->with('createdBy:id,name')
            ->orderByDesc('transaction_date')
            ->orderByDesc('created_at')
            ->limit(200)
            ->get();

        $expenses = Expense::where('petty_cash_account_id', $account->id)
            ->with(['subCategory:id,name,expense_category_id', 'subCategory.category:id,name'])
            ->orderByDesc('expense_date')
            ->orderByDesc('created_at')
            ->limit(200)
            ->get();

        // Unified chronological history — frontend renders one timeline.
        $txItems = $transactions->map(fn ($t) => [
            'id' => $t->id,
            'kind' => $t->type, // top_up | return | adjustment_in | adjustment_out
            'date' => $t->transaction_date?->format('Y-m-d'),
            'amount' => number_format((float) $t->amount, 2, '.', ''),
            'description' => match ($t->type) {
                'top_up' => 'Top-up',
                'return' => 'Cash returned',
                'adjustment_in' => 'Adjustment (gain)',
                'adjustment_out' => 'Adjustment (loss)',
                default => ucfirst((string) $t->type),
            },
            'reference' => $t->reference,
            'notes' => $t->notes,
            'reconciliation_id' => $t->reconciliation_id,
            'created_by' => $t->createdBy?->name,
            'created_at' => $t->created_at?->toIso8601String(),
        ]);

        $expenseItems = $expenses->map(fn ($e) => [
            'id' => $e->id,
            'kind' => 'expense',
            'date' => $e->expense_date?->format('Y-m-d'),
            'amount' => number_format((float) $e->amount, 2, '.', ''),
            'description' => $e->description,
            'reference' => $e->reference,
            'notes' => $e->notes,
            'category' => $e->subCategory?->category?->name,
            'sub_category' => $e->subCategory?->name,
            'created_at' => $e->created_at?->toIso8601String(),
        ]);

        $history = $txItems->merge($expenseItems)
            ->sortByDesc(fn ($i) => $i['date'] . ' ' . ($i['created_at'] ?? ''))
            ->values()
            ->take(200);

        $reconciliations = PettyCashReconciliation::where('petty_cash_account_id', $account->id)
            ->with('createdBy:id,name')
            ->orderByDesc('reconciled_at')
            ->limit(20)
            ->get();

        return response()->json([
            'account' => [
                'id' => $account->id,
                'name' => $account->name,
                'opening_balance' => number_format((float) $account->opening_balance, 2, '.', ''),
                'is_active' => (bool) $account->is_active,
            ],
            'balance' => number_format($balance, 2, '.', ''),
            'history' => $history,
            'reconciliations' => $reconciliations,
        ]);
    }

    /**
     * Record a top-up (money in) or a return (money out). The given_by /
     * received_by fields populate the voucher PDF that the user can download
     * next, print, sign, scan, and upload back via uploadTransactionVoucher.
     */
    public function storeTransaction(Request $request)
    {
        try {
            $validated = $request->validate([
                'type' => 'required|in:top_up,return',
                'amount' => 'required|numeric|min:0.01',
                'transaction_date' => 'required|date|before_or_equal:today',
                'reference' => 'nullable|string|max:255',
                'notes' => 'nullable|string|max:2000',
                'given_by_name' => 'nullable|string|max:255',
                'received_by_name' => 'nullable|string|max:255',
            ]);

            $account = $this->getOrCreateAccount();

            $tx = PettyCashTransaction::create([
                'petty_cash_account_id' => $account->id,
                'created_by' => auth()->id(),
                'type' => $validated['type'],
                'amount' => $validated['amount'],
                'transaction_date' => $validated['transaction_date'],
                'reference' => $validated['reference'] ?? null,
                'notes' => $validated['notes'] ?? null,
                'given_by_name' => $validated['given_by_name'] ?? null,
                'received_by_name' => $validated['received_by_name'] ?? null,
            ]);

            return response()->json([
                'message' => $validated['type'] === 'top_up' ? 'Top-up recorded.' : 'Return recorded.',
                'data' => $tx,
                'balance' => $this->computeBalance($account),
            ]);
        } catch (ValidationException $e) {
            throw $e;
        } catch (\Throwable $e) {
            Log::error('Petty cash transaction failed', [
                'tenant_id' => auth()->user()?->tenant_id,
                'type' => $request->input('type'),
                'amount' => $request->input('amount'),
                'exception' => $e,
            ]);
            return response()->json(['message' => 'Could not record transaction. Please try again.'], 500);
        }
    }

    /**
     * Stream the printable voucher PDF for a transaction.
     */
    public function downloadTransactionVoucher(PettyCashTransaction $transaction)
    {
        try {
            $pdf = app(PdfService::class)->generatePettyCashVoucher($transaction);
            return $pdf->download("voucher-{$transaction->id}.pdf");
        } catch (\Throwable $e) {
            Log::error('Voucher PDF download failed', [
                'transaction_id' => $transaction->id,
                'exception' => $e,
            ]);
            return response()->json(['message' => 'Voucher could not be generated. Please contact support.'], 500);
        }
    }

    /**
     * Attach the signed (scanned) voucher PDF after the physical voucher has
     * been printed and signed. Replaces any previously-attached voucher.
     */
    public function uploadTransactionVoucher(Request $request, PettyCashTransaction $transaction)
    {
        $request->validate([
            'voucher' => 'required|file|max:10240|mimes:pdf,jpg,jpeg,png',
        ]);

        $newPath = null;

        try {
            // Store the new file FIRST so a failure later doesn't leave the
            // transaction pointing at a deleted attachment.
            $newPath = $request->file('voucher')->store('petty-cash/vouchers', 'public');

            // Capture the old path so we can delete it only after the DB update succeeds.
            $oldPath = $transaction->voucher_attachment_path;

            // Update DB to point at the new path.
            $transaction->update(['voucher_attachment_path' => $newPath]);

            // Only now is it safe to remove the previous attachment.
            if ($oldPath && $oldPath !== $newPath) {
                Storage::disk('public')->delete($oldPath);
            }

            return response()->json([
                'message' => 'Signed voucher uploaded.',
                'voucher_attachment_url' => asset('storage/' . $newPath),
            ]);
        } catch (\Throwable $e) {
            // Clean up the orphaned upload — we never successfully linked it.
            if ($newPath) {
                try {
                    Storage::disk('public')->delete($newPath);
                } catch (\Throwable $cleanupError) {
                    Log::error('Failed to clean up orphan voucher upload', [
                        'path' => $newPath,
                        'exception' => $cleanupError,
                    ]);
                }
            }

            Log::error('Voucher upload failed', [
                'transaction_id' => $transaction->id,
                'exception' => $e,
            ]);

            return response()->json(['message' => 'Could not upload voucher. Please try again.'], 500);
        }
    }

    /**
     * Record a cash count. If the user accepts a discrepancy, emit a matching
     * adjustment transaction so the ledger balance equals the counted balance.
     */
    public function storeReconciliation(Request $request)
    {
        try {
            $validated = $request->validate([
                'counted_balance' => 'required|numeric|min:0',
                'reconciled_at' => 'nullable|date|before_or_equal:today',
                'resolution' => 'required|in:accepted,investigating',
                'notes' => 'nullable|string|max:2000',
            ]);

            $account = $this->getOrCreateAccount();
            $ledger = $this->computeBalance($account);
            $counted = round((float) $validated['counted_balance'], 2);
            $diff = round($counted - $ledger, 2);

            $reconciliation = DB::transaction(function () use ($account, $ledger, $counted, $diff, $validated) {
                $reconciliation = PettyCashReconciliation::create([
                    'petty_cash_account_id' => $account->id,
                    'created_by' => auth()->id(),
                    'reconciled_at' => $validated['reconciled_at'] ?? now(),
                    'ledger_balance' => $ledger,
                    'counted_balance' => $counted,
                    'difference' => $diff,
                    'resolution' => $validated['resolution'],
                    'notes' => $validated['notes'] ?? null,
                ]);

                // Accepted + non-zero diff → emit an adjustment so the ledger
                // matches the physical count. Investigating → leave balance untouched.
                if ($validated['resolution'] === 'accepted' && abs($diff) > 0.001) {
                    PettyCashTransaction::create([
                        'petty_cash_account_id' => $account->id,
                        'created_by' => auth()->id(),
                        'type' => $diff > 0 ? 'adjustment_in' : 'adjustment_out',
                        'amount' => abs($diff),
                        'transaction_date' => $reconciliation->reconciled_at->toDateString(),
                        'reconciliation_id' => $reconciliation->id,
                        'reference' => 'Reconciliation #' . substr($reconciliation->id, 0, 8),
                        'notes' => 'Auto-adjustment from cash count',
                    ]);
                }

                return $reconciliation;
            });

            // Compute the post-commit balance outside the transaction so the
            // response reflects the persisted state.
            return response()->json([
                'message' => 'Reconciliation recorded.',
                'data' => $reconciliation->fresh(),
                'balance' => $this->computeBalance($account),
            ]);
        } catch (ValidationException $e) {
            throw $e;
        } catch (\Throwable $e) {
            Log::error('Petty cash reconciliation failed', [
                'tenant_id' => auth()->user()?->tenant_id,
                'counted_balance' => $request->input('counted_balance'),
                'resolution' => $request->input('resolution'),
                'exception' => $e,
            ]);
            return response()->json(['message' => 'Could not record reconciliation. Please try again.'], 500);
        }
    }

    /**
     * Lazy-creates the tenant's single petty cash account on first access.
     * Single-pool design: the UNIQUE(tenant_id) constraint guarantees one row.
     */
    private function getOrCreateAccount(): PettyCashAccount
    {
        if (!auth()->user()) {
            abort(401);
        }

        try {
            return PettyCashAccount::firstOrCreate(
                ['tenant_id' => auth()->user()->tenant_id],
                ['name' => 'Petty Cash', 'opening_balance' => 0, 'is_active' => true]
            );
        } catch (QueryException $e) {
            // Concurrent insert won the UNIQUE(tenant_id) race — fetch the
            // row the other request created.
            return PettyCashAccount::where('tenant_id', auth()->user()->tenant_id)->firstOrFail();
        }
    }

    /**
     * Balance = opening + (top_up + adjustment_in) - (return + adjustment_out) - expenses tagged to this account.
     * One round-trip per group; cheap enough to compute on every read.
     */
    private function computeBalance(PettyCashAccount $account): float
    {
        $opening = (float) $account->opening_balance;

        $tx = PettyCashTransaction::where('petty_cash_account_id', $account->id)
            ->selectRaw("
                COALESCE(SUM(CASE WHEN type IN ('top_up','adjustment_in') THEN amount ELSE 0 END), 0) AS additions,
                COALESCE(SUM(CASE WHEN type IN ('return','adjustment_out') THEN amount ELSE 0 END), 0) AS subtractions
            ")
            ->first();

        $spent = (float) Expense::where('petty_cash_account_id', $account->id)->sum('amount');

        return round($opening + (float) $tx->additions - (float) $tx->subtractions - $spent, 2);
    }
}

<?php

namespace App\Http\Controllers;

use App\Http\Requests\StoreExpenseRequest;
use App\Http\Resources\ExpenseResource;
use App\Models\Expense;
use App\Models\PettyCashAccount;
use App\Services\PdfService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\ValidationException;

class ExpenseController extends Controller
{
    public function index(Request $request)
    {
        $query = Expense::with('subCategory.category');

        if ($request->has('sub_expense_category_id')) {
            $query->where('sub_expense_category_id', $request->sub_expense_category_id);
        }

        if ($request->filled('search')) {
            $query->where('description', 'like', '%' . $request->search . '%');
        }

        if ($request->filled('date_from')) {
            $query->where('expense_date', '>=', $request->date_from);
        }

        if ($request->filled('date_to')) {
            $query->where('expense_date', '<=', $request->date_to);
        }

        return ExpenseResource::collection(
            $query->orderByDesc('expense_date')->paginate($request->per_page ?? 20)
        );
    }

    public function store(StoreExpenseRequest $request)
    {
        $data = $request->safe()->except('attachment');

        // Insufficient-funds guard for petty cash — runs BEFORE the file
        // upload so a rejected expense doesn't orphan an attachment.
        if (!empty($data['petty_cash_account_id'])) {
            $this->assertPettyCashFunds($data['petty_cash_account_id'], (float) $data['amount']);
        }

        $storedPath = null;
        if ($request->hasFile('attachment')) {
            $storedPath = $request->file('attachment')->store('receipts/expenses', 'public');
            $data['attachment_path'] = $storedPath;
        }

        try {
            $expense = Expense::create($data);
        } catch (\Throwable $e) {
            // The model write failed after the file landed on disk — remove
            // the orphan so we don't accumulate unreferenced uploads.
            if ($storedPath) {
                try {
                    Storage::disk('public')->delete($storedPath);
                } catch (\Throwable $cleanupError) {
                    Log::error('Failed to clean up orphan expense attachment', [
                        'path' => $storedPath,
                        'exception' => $cleanupError,
                    ]);
                }
            }
            throw $e;
        }

        return new ExpenseResource($expense->load('subCategory.category'));
    }

    public function show(Expense $expense)
    {
        return new ExpenseResource($expense->load('subCategory.category'));
    }

    public function update(StoreExpenseRequest $request, Expense $expense)
    {
        $data = $request->safe()->except('attachment');

        // Insufficient-funds guard for petty cash — same pre-upload check
        // as store(). Pass the existing expense so its current amount is
        // credited back into the available balance (we're replacing it,
        // not stacking).
        if (!empty($data['petty_cash_account_id'])) {
            $this->assertPettyCashFunds($data['petty_cash_account_id'], (float) $data['amount'], $expense);
        }

        $newPath = null;
        $oldPath = null;
        if ($request->hasFile('attachment')) {
            $newPath = $request->file('attachment')->store('receipts/expenses', 'public');
            $oldPath = $expense->attachment_path;
            $data['attachment_path'] = $newPath;
        }

        try {
            $expense->update($data);
        } catch (\Throwable $e) {
            // Model update failed — clean up the just-uploaded file so we
            // don't leave an orphan referencing nothing.
            if ($newPath) {
                try {
                    Storage::disk('public')->delete($newPath);
                } catch (\Throwable $cleanupError) {
                    Log::error('Failed to clean up orphan expense attachment', [
                        'path' => $newPath,
                        'exception' => $cleanupError,
                    ]);
                }
            }
            throw $e;
        }

        // Now that the DB row points at the new file, retire the old one.
        if ($newPath && $oldPath && $oldPath !== $newPath) {
            Storage::disk('public')->delete($oldPath);
        }

        return new ExpenseResource($expense->load('subCategory.category'));
    }

    public function destroy(Expense $expense)
    {
        // NOTE: Expense uses SoftDeletes. The row is preserved (and could be
        // restored later) so we intentionally do NOT delete the uploaded
        // attachment/voucher files here — hard-deleting them would leave the
        // restored record with broken URLs. A future hard-delete (forceDelete)
        // path should handle file cleanup.
        $expense->delete();

        return response()->json(['message' => 'Expense deleted']);
    }

    /**
     * Hard-block: a new (or updated) petty cash expense cannot exceed the
     * account's committed balance — the cash that is actually still in the
     * till after subtracting pending-voucher expenses. The user can't issue
     * petty cash that isn't there.
     *
     * On update, the existing expense's own amount is credited back into
     * the available balance because we are replacing it, not stacking.
     */
    private function assertPettyCashFunds(string $accountId, float $newAmount, ?Expense $existingExpense = null): void
    {
        $account = PettyCashAccount::find($accountId);
        if (!$account) {
            throw ValidationException::withMessages([
                'petty_cash_account_id' => 'Petty cash account not found.',
            ]);
        }

        $committed = (float) $account->balances()['committed'];

        // If editing an expense already tagged to THIS account, its old
        // amount is already counted in committed — free it up for the check.
        if ($existingExpense && $existingExpense->petty_cash_account_id === $accountId) {
            $committed += (float) $existingExpense->amount;
        }

        // Tiny epsilon to absorb decimal rounding noise.
        if ($newAmount > $committed + 0.0001) {
            throw ValidationException::withMessages([
                'amount' => sprintf(
                    'Insufficient petty cash balance. Available: %s, requested: %s.',
                    number_format($committed, 2),
                    number_format($newAmount, 2)
                ),
            ]);
        }
    }

    /**
     * Generate the printable petty-cash voucher PDF for this expense. Only
     * meaningful when the expense is tagged to a petty cash account, but
     * we don't hard-block — the controller renders whatever data is present.
     */
    public function downloadVoucher(Expense $expense)
    {
        try {
            $pdf = app(PdfService::class)->generatePettyCashVoucher($expense);
            return $pdf->download("voucher-{$expense->id}.pdf");
        } catch (\Throwable $e) {
            Log::error('Expense voucher PDF failed', [
                'expense_id' => $expense->id,
                'exception' => $e,
            ]);
            return response()->json(['message' => 'Voucher could not be generated. Please contact support.'], 500);
        }
    }

    /**
     * Attach the scanned, signed voucher PDF after the physical voucher has
     * been printed and signed. Replaces any previously-attached voucher.
     */
    public function uploadVoucher(Request $request, Expense $expense)
    {
        $request->validate([
            'voucher' => 'required|file|max:10240|mimes:pdf,jpg,jpeg,png',
        ]);

        $newPath = null;

        try {
            // Store the new file FIRST so a failure later doesn't orphan the
            // expense (pointing at a path we already deleted).
            $newPath = $request->file('voucher')->store('petty-cash/vouchers', 'public');

            $oldPath = $expense->voucher_attachment_path;

            $expense->update(['voucher_attachment_path' => $newPath]);

            if ($oldPath && $oldPath !== $newPath) {
                Storage::disk('public')->delete($oldPath);
            }

            return response()->json([
                'message' => 'Signed voucher uploaded.',
                'voucher_attachment_url' => asset('storage/' . $newPath),
            ]);
        } catch (\Throwable $e) {
            // Roll back the orphan upload — DB never got linked to it.
            if ($newPath) {
                try {
                    Storage::disk('public')->delete($newPath);
                } catch (\Throwable $cleanupError) {
                    Log::error('Failed to clean up orphan expense voucher upload', [
                        'path' => $newPath,
                        'exception' => $cleanupError,
                    ]);
                }
            }

            Log::error('Expense voucher upload failed', [
                'expense_id' => $expense->id,
                'exception' => $e,
            ]);

            return response()->json(['message' => 'Could not upload voucher. Please try again.'], 500);
        }
    }
}

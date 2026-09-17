<?php

namespace App\Http\Controllers;

use App\Http\Requests\StoreSystemRecordExpenseRequest;
use App\Http\Resources\SystemRecordExpenseResource;
use App\Models\SystemRecordExpense;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;

/**
 * Tracks what a System Records withdrawal was actually spent on — see
 * SystemRecordExpense migration. Mirrors SystemRecordController's
 * store-file-first / clean-up-on-failure shape for the attachment.
 */
class SystemRecordExpenseController extends Controller
{
    private const RELATIONS = ['systemRecord.system', 'systemRecord.systemProperty', 'createdBy'];

    public function index(Request $request)
    {
        $query = SystemRecordExpense::with(self::RELATIONS);

        if ($request->filled('system_record_id')) {
            $query->where('system_record_id', $request->system_record_id);
        }
        if ($request->filled('date_from')) {
            $query->where('expense_date', '>=', $request->date_from);
        }
        if ($request->filled('date_to')) {
            $query->where('expense_date', '<=', $request->date_to);
        }
        if ($request->filled('search')) {
            $query->where('description', 'like', '%' . $request->search . '%');
        }

        return SystemRecordExpenseResource::collection(
            $query->orderByDesc('expense_date')->orderByDesc('created_at')
                  ->paginate($request->per_page ?? 25)
        );
    }

    public function store(StoreSystemRecordExpenseRequest $request)
    {
        $data = $request->safe()->except('attachment');
        $data['created_by'] = auth()->id();

        $storedPath = null;
        if ($request->hasFile('attachment')) {
            $storedPath = $request->file('attachment')->store('receipts/system-record-expenses', 'public');
            $data['attachment_path'] = $storedPath;
        }

        try {
            $expense = SystemRecordExpense::create($data);
        } catch (\Throwable $e) {
            if ($storedPath) {
                try {
                    Storage::disk('public')->delete($storedPath);
                } catch (\Throwable $cleanupError) {
                    Log::error('Failed to clean up orphan system record expense attachment', [
                        'path' => $storedPath, 'exception' => $cleanupError,
                    ]);
                }
            }
            throw $e;
        }

        return new SystemRecordExpenseResource($expense->load(self::RELATIONS));
    }

    public function show(SystemRecordExpense $system_record_expense)
    {
        return new SystemRecordExpenseResource($system_record_expense->load(self::RELATIONS));
    }

    public function update(StoreSystemRecordExpenseRequest $request, SystemRecordExpense $system_record_expense)
    {
        $data = $request->safe()->except('attachment');

        $newPath = null;
        $oldPath = null;
        if ($request->hasFile('attachment')) {
            $newPath = $request->file('attachment')->store('receipts/system-record-expenses', 'public');
            $oldPath = $system_record_expense->attachment_path;
            $data['attachment_path'] = $newPath;
        }

        try {
            $system_record_expense->update($data);
        } catch (\Throwable $e) {
            if ($newPath) {
                try {
                    Storage::disk('public')->delete($newPath);
                } catch (\Throwable $cleanupError) {
                    Log::error('Failed to clean up orphan system record expense attachment', [
                        'path' => $newPath, 'exception' => $cleanupError,
                    ]);
                }
            }
            throw $e;
        }

        if ($newPath && $oldPath && $oldPath !== $newPath) {
            Storage::disk('public')->delete($oldPath);
        }

        return new SystemRecordExpenseResource($system_record_expense->load(self::RELATIONS));
    }

    public function destroy(SystemRecordExpense $system_record_expense)
    {
        $system_record_expense->delete();
        return response()->json(['message' => 'Expense deleted']);
    }
}

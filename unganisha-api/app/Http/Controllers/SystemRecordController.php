<?php

namespace App\Http\Controllers;

use App\Http\Requests\StoreSystemRecordRequest;
use App\Http\Resources\SystemRecordResource;
use App\Models\SystemRecord;
use App\Models\User;
use App\Notifications\SystemRecordNeedsReconciliationNotification;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Notification;
use Illuminate\Support\Facades\Storage;

class SystemRecordController extends Controller
{
    private const RELATIONS = [
        'system', 'systemProperty', 'bankAccount', 'createdBy', 'smsConfirmedBy', 'statementConfirmedBy',
    ];

    public function index(Request $request)
    {
        $query = SystemRecord::with([
            'system:id,name',
            'systemProperty:id,name',
            'bankAccount:id,bank_name,account_number',
            'createdBy:id,name',
            'smsConfirmedBy:id,name',
            'statementConfirmedBy:id,name',
        ]);

        if ($request->filled('system_id')) {
            $query->where('system_id', $request->system_id);
        }
        if ($request->filled('system_property_id')) {
            $query->where('system_property_id', $request->system_property_id);
        }
        if ($request->filled('bank_account_id')) {
            $query->where('bank_account_id', $request->bank_account_id);
        }
        if ($request->filled('type')) {
            $query->where('type', $request->type);
        }
        if ($request->filled('date_from')) {
            $query->where('record_date', '>=', $request->date_from);
        }
        if ($request->filled('date_to')) {
            $query->where('record_date', '<=', $request->date_to);
        }
        if ($request->filled('search')) {
            $search = $request->search;
            $query->where(fn ($q) => $q
                ->where('notes', 'like', "%{$search}%")
                ->orWhere('transaction_reference', 'like', "%{$search}%"));
        }

        return SystemRecordResource::collection(
            $query->orderByDesc('record_date')->orderByDesc('created_at')
                  ->paginate($request->per_page ?? 25)
        );
    }

    public function store(StoreSystemRecordRequest $request)
    {
        $data = $request->safe()->except('receipt');
        $data['created_by'] = auth()->id();

        // Store the receipt file FIRST so any failure during the DB write
        // doesn't leave us with a row pointing nowhere; on model-write
        // failure we delete the orphaned file before rethrowing.
        $storedPath = null;
        if ($request->hasFile('receipt')) {
            $storedPath = $request->file('receipt')->store('receipts/system-records', 'public');
            $data['receipt_attachment_path'] = $storedPath;
        }

        try {
            $record = SystemRecord::create($data);
        } catch (\Throwable $e) {
            if ($storedPath) {
                try {
                    Storage::disk('public')->delete($storedPath);
                } catch (\Throwable $cleanupError) {
                    Log::error('Failed to clean up orphan system record receipt', [
                        'path' => $storedPath, 'exception' => $cleanupError,
                    ]);
                }
            }
            throw $e;
        }

        // Deposits are the ones needing SMS+statement reconciliation —
        // tell whoever can do that a new one is waiting. Never let a
        // notification failure fail the record creation itself.
        if ($record->type === 'deposit') {
            try {
                $reconcilers = User::withoutGlobalScopes()
                    ->where('tenant_id', $record->tenant_id)
                    ->where('is_active', true)
                    ->get()
                    ->filter(fn ($u) => $u->hasPermission('system_records.reconcile'));

                if ($reconcilers->isNotEmpty()) {
                    Notification::send($reconcilers, new SystemRecordNeedsReconciliationNotification($record));
                }
            } catch (\Throwable $e) {
                Log::warning('SystemRecord: reconciliation notification failed', [
                    'record_id' => $record->id, 'exception' => $e,
                ]);
            }
        }

        return new SystemRecordResource($record->load(self::RELATIONS));
    }

    public function show(SystemRecord $system_record)
    {
        return new SystemRecordResource($system_record->load(self::RELATIONS));
    }

    public function update(StoreSystemRecordRequest $request, SystemRecord $system_record)
    {
        $data = $request->safe()->except('receipt');

        // Store-new → update-DB → delete-old. A disk failure between (1) and (2)
        // cleans up the orphan; the old receipt only goes away after we've
        // confirmed the row points at the new one.
        $newPath = null;
        $oldPath = null;
        if ($request->hasFile('receipt')) {
            $newPath = $request->file('receipt')->store('receipts/system-records', 'public');
            $oldPath = $system_record->receipt_attachment_path;
            $data['receipt_attachment_path'] = $newPath;
        }

        try {
            $system_record->update($data);
        } catch (\Throwable $e) {
            if ($newPath) {
                try {
                    Storage::disk('public')->delete($newPath);
                } catch (\Throwable $cleanupError) {
                    Log::error('Failed to clean up orphan system record receipt', [
                        'path' => $newPath, 'exception' => $cleanupError,
                    ]);
                }
            }
            throw $e;
        }

        if ($newPath && $oldPath && $oldPath !== $newPath) {
            Storage::disk('public')->delete($oldPath);
        }

        return new SystemRecordResource($system_record->load(self::RELATIONS));
    }

    public function destroy(SystemRecord $system_record)
    {
        // Like Expense::destroy — SoftDeletes preserves the row, so we
        // keep the file too. Hard-deleting it would orphan the receipt URL
        // if the record is ever restored.
        $system_record->delete();
        return response()->json(['message' => 'System record deleted']);
    }

    /**
     * Dual-control reconciliation: the person watching for the bank SMS and
     * the person checking the bank statement are normally different staff —
     * each toggles their own check independently. A record only counts as
     * reconciled once both are set (see SystemRecordResource::reconciled).
     */
    public function toggleSmsConfirmation(SystemRecord $system_record)
    {
        // Direct attribute assignment (not update([...])) deliberately
        // bypasses $fillable — these two columns aren't mass-assignable
        // through the general edit form, only through this toggle.
        if ($system_record->sms_confirmed_at) {
            $system_record->sms_confirmed_at = null;
            $system_record->sms_confirmed_by = null;
        } else {
            $system_record->sms_confirmed_at = now();
            $system_record->sms_confirmed_by = auth()->id();
        }
        $system_record->save();

        return new SystemRecordResource($system_record->load(self::RELATIONS));
    }

    public function toggleStatementConfirmation(SystemRecord $system_record)
    {
        if ($system_record->statement_confirmed_at) {
            $system_record->statement_confirmed_at = null;
            $system_record->statement_confirmed_by = null;
        } else {
            $system_record->statement_confirmed_at = now();
            $system_record->statement_confirmed_by = auth()->id();
        }
        $system_record->save();

        return new SystemRecordResource($system_record->load(self::RELATIONS));
    }

    /** Lets whoever is reconciling flag a discrepancy on this record — e.g. "not seen on statement yet". */
    public function updateReconciliationNote(Request $request, SystemRecord $system_record)
    {
        $data = $request->validate(['reconciliation_note' => 'nullable|string|max:1000']);

        $system_record->reconciliation_note = $data['reconciliation_note'] ?? null;
        $system_record->save();

        return new SystemRecordResource($system_record->load(self::RELATIONS));
    }
}

<?php

namespace App\Http\Controllers;

use App\Http\Requests\StoreSystemRecordRequest;
use App\Http\Resources\SystemRecordResource;
use App\Models\SystemRecord;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;

class SystemRecordController extends Controller
{
    public function index(Request $request)
    {
        $query = SystemRecord::with(['system:id,name', 'systemProperty:id,name', 'createdBy:id,name']);

        if ($request->filled('system_id')) {
            $query->where('system_id', $request->system_id);
        }
        if ($request->filled('system_property_id')) {
            $query->where('system_property_id', $request->system_property_id);
        }
        if ($request->filled('date_from')) {
            $query->where('record_date', '>=', $request->date_from);
        }
        if ($request->filled('date_to')) {
            $query->where('record_date', '<=', $request->date_to);
        }
        if ($request->filled('search')) {
            $query->where('notes', 'like', '%' . $request->search . '%');
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

        return new SystemRecordResource($record->load('system', 'systemProperty', 'createdBy'));
    }

    public function show(SystemRecord $system_record)
    {
        return new SystemRecordResource($system_record->load('system', 'systemProperty', 'createdBy'));
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

        return new SystemRecordResource($system_record->load('system', 'systemProperty', 'createdBy'));
    }

    public function destroy(SystemRecord $system_record)
    {
        // Like Expense::destroy — SoftDeletes preserves the row, so we
        // keep the file too. Hard-deleting it would orphan the receipt URL
        // if the record is ever restored.
        $system_record->delete();
        return response()->json(['message' => 'System record deleted']);
    }
}

<?php

namespace App\Http\Controllers;

use App\Http\Requests\StoreSystemRecordRequest;
use App\Http\Resources\SystemRecordResource;
use App\Models\SystemRecord;
use Illuminate\Http\Request;

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
        $record = SystemRecord::create($request->validated() + [
            'created_by' => auth()->id(),
        ]);
        return new SystemRecordResource($record->load('system', 'systemProperty', 'createdBy'));
    }

    public function show(SystemRecord $system_record)
    {
        return new SystemRecordResource($system_record->load('system', 'systemProperty', 'createdBy'));
    }

    public function update(StoreSystemRecordRequest $request, SystemRecord $system_record)
    {
        $system_record->update($request->validated());
        return new SystemRecordResource($system_record->load('system', 'systemProperty', 'createdBy'));
    }

    public function destroy(SystemRecord $system_record)
    {
        $system_record->delete();
        return response()->json(['message' => 'System record deleted']);
    }
}

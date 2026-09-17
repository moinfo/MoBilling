<?php

namespace App\Http\Controllers;

use App\Http\Requests\StoreWorkLocationRequest;
use App\Http\Resources\WorkLocationResource;
use App\Models\WorkLocation;
use Illuminate\Http\Request;

/**
 * Offices/sites staff self-check-in is geofenced against — see
 * AttendanceController::checkIn().
 */
class WorkLocationController extends Controller
{
    public function index(Request $request)
    {
        $query = WorkLocation::withCount('staff');

        if ($request->filled('search')) {
            $query->where('name', 'like', '%' . $request->search . '%');
        }

        return WorkLocationResource::collection(
            $query->orderBy('name')->paginate($request->per_page ?? 50)
        );
    }

    public function store(StoreWorkLocationRequest $request)
    {
        $location = WorkLocation::create($request->validated());
        return new WorkLocationResource($location);
    }

    public function show(WorkLocation $work_location)
    {
        return new WorkLocationResource($work_location->loadCount('staff'));
    }

    public function update(StoreWorkLocationRequest $request, WorkLocation $work_location)
    {
        $work_location->update($request->validated());
        return new WorkLocationResource($work_location->loadCount('staff'));
    }

    /**
     * Refuses when staff are still assigned — an assignment pointing at a
     * deleted location is a silent dead end for their next check-in
     * attempt, not a graceful one.
     */
    public function destroy(WorkLocation $work_location)
    {
        if ($work_location->staff()->exists()) {
            return response()->json([
                'message' => 'Reassign the staff at this location before deleting it.',
            ], 422);
        }

        $work_location->delete();
        return response()->json(['message' => 'Work location deleted']);
    }
}

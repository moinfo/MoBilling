<?php

namespace App\Http\Controllers;

use App\Http\Requests\StoreWorkLocationRequest;
use App\Http\Resources\WorkLocationResource;
use App\Models\User;
use App\Models\WorkLocation;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

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

    /** All active tenant staff + their current work location — for the assignment table. */
    public function staffAssignments()
    {
        $tenantId = auth()->user()->tenant_id;

        $users = User::with('workLocation:id,name')
            ->where('tenant_id', $tenantId)
            ->where('is_active', true)
            ->orderBy('name')
            ->get(['id', 'name', 'work_location_id']);

        return response()->json([
            'data' => $users->map(fn ($u) => $this->formatStaffAssignment($u)),
        ]);
    }

    /** Assigns (or clears, when null) one staff member's work location. */
    public function assignStaff(Request $request, string $userId)
    {
        $tenantId = auth()->user()->tenant_id;
        $user = User::where('tenant_id', $tenantId)->findOrFail($userId);

        $data = $request->validate([
            'work_location_id' => [
                'nullable', 'uuid',
                Rule::exists('work_locations', 'id')->where('tenant_id', $tenantId),
            ],
        ]);

        $user->update(['work_location_id' => $data['work_location_id'] ?? null]);
        $user->load('workLocation:id,name');

        return response()->json(['data' => $this->formatStaffAssignment($user)]);
    }

    private function formatStaffAssignment(User $u): array
    {
        return [
            'id' => $u->id,
            'name' => $u->name,
            'work_location' => $u->workLocation ? ['id' => $u->workLocation->id, 'name' => $u->workLocation->name] : null,
        ];
    }
}

<?php

namespace App\Http\Controllers;

use App\Models\LeaveBalance;
use App\Models\LeaveRequest;
use App\Models\LeaveType;
use App\Models\User;
use App\Notifications\LeaveRequestDecidedNotification;
use App\Notifications\LeaveRequestSubmittedNotification;
use App\Services\AttendanceService;
use App\Traits\AuthorizesPermissions;
use Carbon\CarbonPeriod;
use Illuminate\Http\Request;

class LeaveRequestController extends Controller
{
    use AuthorizesPermissions;

    public function __construct(private AttendanceService $attendanceService)
    {
    }

    /**
     * Three-tier visibility cascade — copied in structure from
     * StaffReportsController::index(): leave.view_all sees everything,
     * leave.review sees their own + assigned subordinates', everyone else
     * sees only their own requests.
     */
    public function index(Request $request)
    {
        $user = auth()->user();
        $query = LeaveRequest::with(['user', 'leaveType', 'reviewer'])
            ->whereHas('user', fn ($q) => $q->where('is_active', true))
            ->orderByDesc('created_at');

        if ($user->hasPermission('leave.view_all')) {
            // no extra filter — everyone in the tenant
        } elseif ($user->hasPermission('leave.review')) {
            $subordinateIds = User::where('tenant_id', $user->tenant_id)
                ->where('supervisor_id', $user->id)
                ->where('is_active', true)
                ->pluck('id')
                ->push($user->id);
            $query->whereIn('user_id', $subordinateIds);
        } else {
            $query->where('user_id', $user->id);
        }

        if ($request->status) $query->where('status', $request->status);
        if ($request->user_id) $query->where('user_id', $request->user_id);

        return response()->json(['data' => $query->get()]);
    }

    /** Self-service: request own leave. Any authenticated user may call this. */
    public function store(Request $request)
    {
        $user = auth()->user();
        $tenantId = $user->tenant_id;

        $data = $request->validate([
            'leave_type_id' => ['required', 'uuid', \Illuminate\Validation\Rule::exists('leave_types', 'id')->where('tenant_id', $tenantId)],
            'start_date' => 'required|date',
            'end_date' => 'required|date|after_or_equal:start_date',
            'reason' => 'nullable|string|max:2000',
        ]);

        $days = \Carbon\Carbon::parse($data['start_date'])->diffInDays(\Carbon\Carbon::parse($data['end_date'])) + 1;

        $leaveRequest = LeaveRequest::create([
            'tenant_id' => $tenantId,
            'user_id' => $user->id,
            'leave_type_id' => $data['leave_type_id'],
            'start_date' => $data['start_date'],
            'end_date' => $data['end_date'],
            'days' => $days,
            'reason' => $data['reason'] ?? null,
            'status' => 'pending',
        ]);
        $leaveRequest->load(['user', 'leaveType']);

        $supervisor = $user->supervisor;
        if ($supervisor) {
            $supervisor->notify(new LeaveRequestSubmittedNotification($user->tenant, $leaveRequest));
        }

        return response()->json(['data' => $leaveRequest], 201);
    }

    /** Requester can cancel their own still-pending request. */
    public function cancel(LeaveRequest $leaveRequest)
    {
        if ($leaveRequest->user_id !== auth()->id()) {
            abort(403);
        }
        if ($leaveRequest->status !== 'pending') {
            abort(422, 'Only a pending request can be cancelled.');
        }

        $leaveRequest->update(['status' => 'cancelled']);

        return response()->json(['data' => $leaveRequest]);
    }

    /** Approve or reject — gated to the reviewer's own subordinates unless leave.view_all. */
    public function review(Request $request, LeaveRequest $leaveRequest)
    {
        $this->authorizePermission('leave.review', 'leave.view_all');
        $reviewer = auth()->user();

        if (!$reviewer->hasPermission('leave.view_all')) {
            $isSubordinate = User::where('id', $leaveRequest->user_id)
                ->where('supervisor_id', $reviewer->id)->exists();
            if (!$isSubordinate) {
                abort(403, 'You can only review your own team\'s leave requests.');
            }
        }

        if ($leaveRequest->status !== 'pending') {
            abort(422, 'This request has already been decided.');
        }

        $data = $request->validate([
            'decision' => 'required|in:approved,rejected',
            'review_note' => 'nullable|string|max:2000',
        ]);

        $leaveRequest->update([
            'status' => $data['decision'],
            'reviewed_by' => $reviewer->id,
            'reviewed_at' => now(),
            'review_note' => $data['review_note'] ?? null,
        ]);
        $leaveRequest->load(['user', 'leaveType', 'reviewer']);

        if ($data['decision'] === 'approved') {
            $period = CarbonPeriod::create($leaveRequest->start_date, $leaveRequest->end_date);
            foreach ($period as $date) {
                $this->attendanceService->markExcused(
                    $leaveRequest->user,
                    $date->toDateString(),
                    'leave',
                    $leaveRequest->leaveType->name,
                );
            }
        }

        $leaveRequest->user->notify(new LeaveRequestDecidedNotification($leaveRequest->user->tenant, $leaveRequest));

        return response()->json(['data' => $leaveRequest]);
    }

    /** Self-service: the logged-in user's own current-year balance per leave type. */
    public function myBalance(Request $request)
    {
        $user = auth()->user();
        $year = (int) $request->query('year', now()->year);

        $types = LeaveType::where('tenant_id', $user->tenant_id)->where('is_active', true)->orderBy('name')->get();
        $allocations = LeaveBalance::where('user_id', $user->id)->where('year', $year)->get()->keyBy('leave_type_id');

        $used = LeaveRequest::where('user_id', $user->id)
            ->whereIn('status', ['approved'])
            ->whereYear('start_date', $year)
            ->get()
            ->groupBy('leave_type_id')
            ->map(fn ($rows) => (int) $rows->sum('days'));

        $data = $types->map(function ($type) use ($allocations, $used) {
            $allocated = (int) ($allocations->get($type->id)?->allocated_days ?? $type->days_per_year);
            $usedDays = (int) ($used->get($type->id) ?? 0);

            return [
                'leave_type' => $type,
                'allocated_days' => $allocated,
                'used_days' => $usedDays,
                'remaining_days' => max(0, $allocated - $usedDays),
            ];
        })->values();

        return response()->json(['data' => $data]);
    }
}

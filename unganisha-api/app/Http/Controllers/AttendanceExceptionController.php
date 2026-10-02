<?php

namespace App\Http\Controllers;

use App\Models\AttendanceExceptionRequest;
use App\Models\AttendancePenalty;
use App\Notifications\AttendanceExceptionDecidedNotification;
use App\Notifications\AttendanceExceptionSubmittedNotification;
use App\Services\AttendanceService;
use App\Traits\AuthorizesPermissions;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Self-service "I had permission / I was out of office" explanation for a
 * day already flagged in the attendance report (absent/late/no-checkout),
 * with an attendance.manage-holder approving or rejecting it — see
 * AttendanceController's report()/buildReport() for the flagged days this
 * is explaining, and AttendanceService::markExcused() for what an approval
 * actually does to that day (same call LeaveRequestController::review() and
 * AttendanceController::record() already make).
 */
class AttendanceExceptionController extends Controller
{
    use AuthorizesPermissions;

    public function __construct(private AttendanceService $attendanceService)
    {
    }

    /** attendance.manage holders see every staff member's requests; everyone else sees only their own. */
    public function index(Request $request)
    {
        $user = auth()->user();
        $query = AttendanceExceptionRequest::with(['user', 'reviewer'])
            ->whereHas('user', fn ($q) => $q->where('is_active', true))
            ->orderByDesc('date');

        if (!$user->hasPermission('attendance.manage')) {
            $query->where('user_id', $user->id);
        }

        if ($request->status)  $query->where('status', $request->status);
        if ($request->user_id) $query->where('user_id', $request->user_id);

        return response()->json(['data' => $query->get()]);
    }

    /** Self-service: explain one of my own flagged days. Any authenticated user may call this. */
    public function store(Request $request)
    {
        $user = auth()->user();

        $data = $request->validate([
            'date' => 'required|date|before_or_equal:today',
            'type' => 'required|in:leave,field,other',
            'comment' => 'required|string|max:2000',
        ]);

        $exists = AttendanceExceptionRequest::where('user_id', $user->id)
            ->where('date', $data['date'])->where('status', 'pending')->exists();
        abort_if($exists, 422, 'You already have a pending explanation for this day.');

        $settings = $this->attendanceService->settings();
        abort_unless(
            $this->attendanceService->isWithinExplainWindow($data['date'], $settings),
            422,
            'The explanation window for this day is closed or not open yet.'
        );

        $exception = AttendanceExceptionRequest::create([
            'tenant_id' => $user->tenant_id,
            'user_id' => $user->id,
            'date' => $data['date'],
            'type' => $data['type'],
            'comment' => $data['comment'],
            'status' => 'pending',
        ]);
        $exception->load('user');

        $supervisor = $user->supervisor;
        if ($supervisor) {
            $supervisor->notify(new AttendanceExceptionSubmittedNotification($user->tenant, $exception));
        }

        return response()->json(['data' => $exception], 201);
    }

    /** Requester can edit their own still-pending explanation before it's decided. */
    public function update(Request $request, AttendanceExceptionRequest $attendanceExceptionRequest)
    {
        if ($attendanceExceptionRequest->user_id !== auth()->id()) {
            abort(403);
        }
        if ($attendanceExceptionRequest->status !== 'pending') {
            abort(422, 'Only a pending explanation can be edited.');
        }

        $data = $request->validate([
            'type' => 'required|in:leave,field,other',
            'comment' => 'required|string|max:2000',
        ]);

        $attendanceExceptionRequest->update($data);
        $attendanceExceptionRequest->load('user');

        return response()->json(['data' => $attendanceExceptionRequest]);
    }

    /** Requester can cancel their own still-pending explanation. */
    public function cancel(AttendanceExceptionRequest $attendanceExceptionRequest)
    {
        if ($attendanceExceptionRequest->user_id !== auth()->id()) {
            abort(403);
        }
        if ($attendanceExceptionRequest->status !== 'pending') {
            abort(422, 'Only a pending explanation can be cancelled.');
        }

        $attendanceExceptionRequest->delete();

        return response()->json(['message' => 'Cancelled.']);
    }

    /** Approve or reject — attendance.manage only. */
    public function review(Request $request, AttendanceExceptionRequest $attendanceExceptionRequest)
    {
        $this->authorizePermission('attendance.manage');

        if ($attendanceExceptionRequest->status !== 'pending') {
            abort(422, 'This explanation has already been decided.');
        }

        $data = $request->validate([
            'decision' => ['required', Rule::in(['approved', 'rejected'])],
            'review_note' => 'nullable|string|max:2000',
        ]);

        $attendanceExceptionRequest->update([
            'status' => $data['decision'],
            'reviewed_by' => auth()->id(),
            'reviewed_at' => now(),
            'review_note' => $data['review_note'] ?? null,
        ]);
        $attendanceExceptionRequest->load(['user', 'reviewer']);

        if ($data['decision'] === 'approved') {
            if ($attendanceExceptionRequest->type === 'other') {
                // No real leave/field category fits, so the attendance
                // record stays exactly as it happened — only the day's
                // unwaived deduction(s) are forgiven, same paper trail
                // (waived_by/waived_at/waive_reason) a manual waive leaves
                // via AttendanceController::waivePenalty().
                AttendancePenalty::where('user_id', $attendanceExceptionRequest->user_id)
                    ->whereDate('date', $attendanceExceptionRequest->date->toDateString())
                    ->where('waived', false)
                    ->update([
                        'waived' => true,
                        'waived_by' => auth()->id(),
                        'waived_at' => now(),
                        'waive_reason' => $data['review_note'] ?? ('Explanation approved: ' . $attendanceExceptionRequest->comment),
                    ]);
            } else {
                $this->attendanceService->markExcused(
                    $attendanceExceptionRequest->user,
                    $attendanceExceptionRequest->date->toDateString(),
                    $attendanceExceptionRequest->type,
                    $attendanceExceptionRequest->comment,
                );
            }
        }

        $attendanceExceptionRequest->user->notify(
            new AttendanceExceptionDecidedNotification($attendanceExceptionRequest->user->tenant, $attendanceExceptionRequest)
        );

        return response()->json(['data' => $attendanceExceptionRequest]);
    }
}

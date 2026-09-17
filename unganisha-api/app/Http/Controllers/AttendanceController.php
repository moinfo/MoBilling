<?php

namespace App\Http\Controllers;

use App\Models\Attendance;
use App\Models\AttendancePenalty;
use App\Models\User;
use App\Models\WorkLocation;
use App\Services\AttendanceService;
use App\Traits\AuthorizesPermissions;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class AttendanceController extends Controller
{
    use AuthorizesPermissions;

    public function __construct(private AttendanceService $attendanceService)
    {
    }

    /** Personal dashboard: today's status + this month's summary & deductions. */
    public function mine()
    {
        $user = auth()->user();
        $s    = $this->attendanceService->settings();
        $today = Attendance::where('user_id', $user->id)->whereDate('date', now()->toDateString())->first();

        $monthStart = now()->startOfMonth()->toDateString();
        $monthEnd   = now()->endOfMonth()->toDateString();

        $records = Attendance::where('user_id', $user->id)
            ->whereBetween('date', [$monthStart, $monthEnd])->orderByDesc('date')->get();

        $penalties = AttendancePenalty::where('user_id', $user->id)->where('waived', false)
            ->whereBetween('date', [$monthStart, $monthEnd])->orderByDesc('date')->get();

        return response()->json(['data' => [
            'settings' => [
                'check_in_time'  => $s->check_in_time,
                'check_out_time' => $s->check_out_time,
                'penalties_enabled' => (bool) $s->penalties_enabled,
                'penalty_absent'      => (float) $s->penalty_absent,
                'penalty_late'        => (float) $s->penalty_late,
                'penalty_left_early'  => (float) $s->penalty_left_early,
                'penalty_no_checkout' => (float) $s->penalty_no_checkout,
            ],
            'today' => $today ? $this->attendanceService->formatDay($today, $s) : null,
            'month_label'   => now()->format('M Y'),
            'present_days'  => $records->whereNotNull('check_in_at')->count(),
            'month_records' => $records->map(fn ($a) => $this->attendanceService->formatDay($a, $s))->values(),
            'deduction_total' => round((float) $penalties->sum('amount'), 2),
            'deduction_by_type' => collect(['absent', 'late', 'left_early', 'no_checkout'])
                ->mapWithKeys(fn ($t) => [$t => (int) $penalties->where('penalty_type', $t)->count()]),
            'deductions' => $penalties->map(fn ($p) => [
                'id'   => $p->id,
                'date' => $p->date->format('Y-m-d'),
                'penalty_type' => $p->penalty_type,
                'amount' => round((float) $p->amount, 2),
                'notes'  => $p->notes,
            ])->values(),
        ]]);
    }

    /** Attendance-clerk view: all active staff + their marks for a date. */
    public function day(Request $request)
    {
        $this->authorizePermission('attendance.manage');
        $date = $request->query('date', now()->toDateString());
        $s = $this->attendanceService->settings();

        $users = User::where('tenant_id', auth()->user()->tenant_id)
            ->where('is_active', true)->orderBy('name')->get(['id', 'name']);
        $records = Attendance::whereDate('date', $date)->get()->keyBy('user_id');

        $staff = $users->map(function ($u) use ($records, $s, $date) {
            $att = $records->get($u->id);
            $day = $att ? $this->attendanceService->formatDay($att, $s) : [
                'date' => $date, 'status' => null, 'status_note' => null, 'check_in_at' => null, 'check_out_at' => null,
                'absent' => true, 'late' => false, 'left_early' => false, 'no_checkout' => false,
            ];
            return ['user' => ['id' => $u->id, 'name' => $u->name]] + $day;
        });

        return response()->json(['data' => [
            'date' => $date,
            'check_in_time'  => $s->check_in_time,
            'check_out_time' => $s->check_out_time,
            'staff' => $staff,
        ]]);
    }

    /** Clerk records/updates one staff member's check-in/out for a date. */
    public function record(Request $request)
    {
        $this->authorizePermission('attendance.manage');
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'user_id'     => ['required', Rule::exists('users', 'id')->where('tenant_id', $tenantId)],
            'date'        => 'required|date',
            'status'      => ['nullable', Rule::in(Attendance::EXCUSED)], // leave|sick|field, null = normal
            'status_note' => 'nullable|string|max:255',
            'check_in'    => 'nullable|date_format:H:i',
            'check_out'   => 'nullable|date_format:H:i',
        ]);

        $date = Carbon::parse($data['date']);
        $excused = !empty($data['status']);

        if ($excused) {
            // Shared with LeaveRequestController::review() — an approved
            // leave request marks every day in its range the exact same way.
            $user = User::findOrFail($data['user_id']);
            $att = $this->attendanceService->markExcused($user, $date->toDateString(), $data['status'], $data['status_note'] ?? null);
            $f = $this->attendanceService->formatDay($att, $this->attendanceService->settings());

            return response()->json(['data' => ['user' => ['id' => $att->user_id]] + $f]);
        }

        $att = Attendance::firstOrNew(['user_id' => $data['user_id'], 'date' => $date->toDateString()]);
        $att->tenant_id ??= $tenantId;
        $att->status      = null;
        $att->status_note = null;
        $att->check_in_at  = !empty($data['check_in'])  ? $date->copy()->setTimeFromTimeString($data['check_in'])  : null;
        $att->check_out_at = !empty($data['check_out']) ? $date->copy()->setTimeFromTimeString($data['check_out']) : null;
        $att->save();

        // Immediately drop unwaived charges the edit just contradicted (a
        // filled check-in clears "absent", etc.) — same rule the nightly
        // reconcile applies, but instant.
        $s = $this->attendanceService->settings();
        $f = $this->attendanceService->formatDay($att, $s);
        $stillValid = array_keys(array_filter([
            'absent'      => $f['absent'],
            'late'        => $f['late'],
            'left_early'  => $f['left_early'],
            'no_checkout' => $f['no_checkout'],
        ]));
        AttendancePenalty::where('user_id', $att->user_id)
            ->whereDate('date', $att->date->toDateString())
            ->where('waived', false)
            ->when($stillValid, fn ($q) => $q->whereNotIn('penalty_type', $stillValid))
            ->delete();

        return response()->json(['data' => ['user' => ['id' => $att->user_id]] + $f]);
    }

    /** Attendance overview: today's snapshot + this month's per-staff summary. */
    public function dashboard(Request $request)
    {
        $this->authorizePermission('attendance.manage');
        $tenantId = auth()->user()->tenant_id;
        $s = $this->attendanceService->settings();

        $users = User::where('tenant_id', $tenantId)->where('is_active', true)->orderBy('name')->get(['id', 'name']);
        $today = now()->toDateString();
        $todayRecs = Attendance::whereDate('date', $today)->get()->keyBy('user_id');

        $t = ['total' => $users->count(), 'present' => 0, 'late' => 0, 'left_early' => 0, 'excused' => 0, 'not_recorded' => 0];
        foreach ($users as $u) {
            $day = $todayRecs->get($u->id);
            $f = $day ? $this->attendanceService->formatDay($day, $s) : null;
            if ($f && $f['status']) {
                $t['excused']++;                 // leave / sick / field duty — not counted absent
            } elseif (!$f || !$f['check_in_at']) {
                $t['not_recorded']++;
            } else {
                $t['present']++;
                if ($f['late']) $t['late']++;
                if ($f['left_early']) $t['left_early']++;
            }
        }

        // This month
        $monthStart = now()->startOfMonth()->toDateString();
        $monthEnd   = now()->endOfMonth()->toDateString();
        $workDays = $s->working_days ?: [1, 2, 3, 4, 5, 6];
        $holidays = \App\Models\StaffReportHoliday::pluck('date')->map(fn ($d) => $d->toDateString())->all();
        $workedSoFar = 0;
        for ($d = now()->startOfMonth(); $d->lte(now()); $d->addDay()) {
            if (in_array($d->dayOfWeekIso, $workDays) && !in_array($d->toDateString(), $holidays, true)) {
                $workedSoFar++;
            }
        }

        $pens = AttendancePenalty::where('waived', false)->whereBetween('date', [$monthStart, $monthEnd])->get();
        $recs = Attendance::whereBetween('date', [$monthStart, $monthEnd])->get();

        $staff = $users->map(function ($u) use ($recs, $pens) {
            $mine = $recs->where('user_id', $u->id);
            return [
                'user' => ['id' => $u->id, 'name' => $u->name],
                'present_days' => $mine->whereNotNull('check_in_at')->count(),
                'deductions'   => round((float) $pens->where('user_id', $u->id)->sum('amount'), 2),
            ];
        })->sortByDesc('deductions')->values();

        return response()->json(['data' => [
            'today' => $t,
            'month_label' => now()->format('M Y'),
            'working_days_so_far' => $workedSoFar,
            'deduction_total' => round((float) $pens->sum('amount'), 2),
            'by_type' => collect(['absent', 'late', 'left_early', 'no_checkout'])
                ->mapWithKeys(fn ($tp) => [$tp => (int) $pens->where('penalty_type', $tp)->count()]),
            'staff' => $staff,
        ]]);
    }

    /** Monthly check-in/out report for one staff member (attendance clerk). */
    public function report(Request $request)
    {
        $this->authorizePermission('attendance.manage');
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'user_id' => ['required', Rule::exists('users', 'id')->where('tenant_id', $tenantId)],
            'month'   => 'nullable|integer|min:1|max:12',
            'year'    => 'nullable|integer|min:2020|max:2100',
        ]);

        $user = User::where('tenant_id', $tenantId)->findOrFail($data['user_id']);

        return response()->json(['data' => $this->buildReport($user, $data)]);
    }

    /** Export the monthly report as PDF or CSV (Excel-friendly). */
    public function exportReport(Request $request)
    {
        $this->authorizePermission('attendance.manage');
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'user_id' => ['required', Rule::exists('users', 'id')->where('tenant_id', $tenantId)],
            'month'   => 'nullable|integer|min:1|max:12',
            'year'    => 'nullable|integer|min:2020|max:2100',
            'format'  => 'required|in:pdf,csv',
        ]);

        $user = User::where('tenant_id', $tenantId)->findOrFail($data['user_id']);
        $report = $this->buildReport($user, $data);
        $slug = \Illuminate\Support\Str::slug($user->name) . '-' . \Illuminate\Support\Str::slug($report['month_label']);

        if ($data['format'] === 'pdf') {
            $tenant = auth()->user()->tenant;
            $pdf = \Barryvdh\DomPDF\Facade\Pdf::loadView('pdf.attendance-report', [
                'report' => $report,
                'tenant' => $tenant,
            ]);

            return $pdf->download("attendance-{$slug}.pdf");
        }

        // CSV (opens directly in Excel)
        $rows = [['Date', 'Day', 'Check-in', 'Check-out', 'Status', 'Deduction']];
        foreach ($report['days'] as $d) {
            $status = $d['holiday'] ? 'Holiday'
                : (!$d['working'] ? 'Off day'
                : ($d['status'] ?: ($d['absent'] ? 'Absent'
                : (implode(' + ', array_filter([$d['late'] ? 'Late' : null, $d['left_early'] ? 'Left early' : null, $d['no_checkout'] ? 'No check-out' : null])) ?: 'Present'))));
            $rows[] = [$d['date'], $d['weekday'], $d['check_in_at'] ?? '', $d['check_out_at'] ?? '', $status, $d['deduction'] ?: ''];
        }
        $rows[] = [];
        $rows[] = ['Totals', '', "Present: {$report['totals']['present']}", "Late: {$report['totals']['late']}", "Absent: {$report['totals']['absent']}", "Deductions: {$report['totals']['deduction_total']}"];

        $csv = fopen('php://temp', 'r+');
        fwrite($csv, "\xEF\xBB\xBF");   // BOM so Excel reads UTF-8
        foreach ($rows as $r) {
            fputcsv($csv, $r);
        }
        rewind($csv);

        return response(stream_get_contents($csv), 200, [
            'Content-Type' => 'text/csv; charset=UTF-8',
            'Content-Disposition' => "attachment; filename=attendance-{$slug}.csv",
        ]);
    }

    /** The same monthly report, but always for the logged-in user themselves. */
    public function myReport(Request $request)
    {
        $data = $request->validate([
            'month' => 'nullable|integer|min:1|max:12',
            'year'  => 'nullable|integer|min:2020|max:2100',
        ]);

        return response()->json(['data' => $this->buildReport(auth()->user(), $data)]);
    }

    /** Day-by-day month report shared by the clerk view and self view. */
    private function buildReport(User $user, array $data): array
    {
        $s = $this->attendanceService->settings();
        $start = Carbon::createFromDate((int) ($data['year'] ?? now()->year), (int) ($data['month'] ?? now()->month), 1)->startOfMonth();
        $end = $start->copy()->endOfMonth();
        $last = $end->isFuture() ? now() : $end;   // don't report days that haven't happened
        $recs = Attendance::where('user_id', $user->id)
            ->whereBetween('date', [$start->toDateString(), $end->toDateString()])
            ->get()->keyBy(fn ($a) => $a->date->toDateString());

        $workDays = $s->working_days ?: [1, 2, 3, 4, 5, 6];
        $holidays = \App\Models\StaffReportHoliday::pluck('date')->map(fn ($d) => $d->toDateString())->flip();

        // Actual charges per day (what was really deducted, waived excluded).
        $penalties = AttendancePenalty::where('user_id', $user->id)->where('waived', false)
            ->whereBetween('date', [$start->toDateString(), $end->toDateString()])
            ->get()->groupBy(fn ($p) => $p->date->toDateString());

        $days = [];
        $totals = ['present' => 0, 'late' => 0, 'left_early' => 0, 'no_checkout' => 0, 'absent' => 0, 'excused' => 0, 'deduction_total' => 0.0];

        for ($d = $start->copy(); $d->lte($last); $d->addDay()) {
            $key = $d->toDateString();
            $working = in_array($d->dayOfWeekIso, $workDays) && !$holidays->has($key);
            $att = $recs->get($key);
            $f = $att ? $this->attendanceService->formatDay($att, $s) : null;

            $row = [
                'date'         => $key,
                'weekday'      => $d->format('D'),
                'working'      => $working,
                'holiday'      => $holidays->has($key),
                'status'       => $f['status'] ?? null,
                'check_in_at'  => $f['check_in_at'] ?? null,
                'check_out_at' => $f['check_out_at'] ?? null,
                'late'         => $f['late'] ?? false,
                'left_early'   => $f['left_early'] ?? false,
                'no_checkout'  => $f['no_checkout'] ?? false,
                // Absent only matters on a working day.
                'absent'       => $working && (($f['absent'] ?? true) && !($f['status'] ?? null)),
                'deduction'    => round((float) ($penalties->get($key)?->sum('amount') ?? 0), 2),
            ];
            $days[] = $row;
            $totals['deduction_total'] += $row['deduction'];

            if ($row['status']) {
                $totals['excused']++;
            } elseif ($row['check_in_at']) {
                $totals['present']++;
                if ($row['late']) $totals['late']++;
                if ($row['left_early']) $totals['left_early']++;
                if ($row['no_checkout']) $totals['no_checkout']++;
            } elseif ($row['absent']) {
                $totals['absent']++;
            }
        }

        return [
            'user'        => ['id' => $user->id, 'name' => $user->name],
            'month_label' => $start->format('F Y'),
            'check_in_time'  => $s->check_in_time,
            'check_out_time' => $s->check_out_time,
            'days'   => $days,
            'totals' => array_merge($totals, ['deduction_total' => round($totals['deduction_total'], 2)]),
        ];
    }

    /** Deductions overview: every staff member's attendance penalties for a month. */
    public function penalties(Request $request)
    {
        $this->authorizePermission('attendance.manage');

        $month = (int) $request->query('month', now()->month);
        $year  = (int) $request->query('year', now()->year);
        $start = Carbon::createFromDate($year, $month, 1)->startOfMonth();
        $end   = $start->copy()->endOfMonth();

        $rows = AttendancePenalty::with('user:id,name')
            ->whereBetween('date', [$start->toDateString(), $end->toDateString()])
            ->orderByDesc('date')->get();

        $staff = $rows->groupBy('user_id')->map(function ($rs) {
            $active = $rs->where('waived', false);
            return [
                'user'    => ['id' => $rs->first()->user_id, 'name' => $rs->first()->user?->name ?? 'Unknown'],
                'total'   => round((float) $active->sum('amount'), 2),
                'by_type' => collect(['absent', 'late', 'left_early', 'no_checkout'])
                    ->mapWithKeys(fn ($t) => [$t => (int) $active->where('penalty_type', $t)->count()]),
                'items'   => $rs->map(fn ($p) => [
                    'id' => $p->id, 'date' => $p->date->format('Y-m-d'),
                    'penalty_type' => $p->penalty_type, 'amount' => round((float) $p->amount, 2),
                    'notes' => $p->notes, 'waived' => (bool) $p->waived, 'waive_reason' => $p->waive_reason,
                ])->values(),
            ];
        })->sortByDesc('total')->values();

        return response()->json(['data' => [
            'month_label' => $start->format('M Y'),
            'grand_total' => round((float) $rows->where('waived', false)->sum('amount'), 2),
            'staff'       => $staff,
        ]]);
    }

    public function waivePenalty(Request $request, AttendancePenalty $attendancePenalty)
    {
        $this->authorizePermission('attendance.manage');
        $data = $request->validate(['reason' => 'nullable|string|max:255']);
        $attendancePenalty->update([
            'waived' => true, 'waived_by' => auth()->id(), 'waived_at' => now(), 'waive_reason' => $data['reason'] ?? null,
        ]);
        return response()->json(['message' => 'Deduction waived.']);
    }

    public function unwaivePenalty(AttendancePenalty $attendancePenalty)
    {
        $this->authorizePermission('attendance.manage');
        $attendancePenalty->update(['waived' => false, 'waived_by' => null, 'waived_at' => null, 'waive_reason' => null]);
        return response()->json(['message' => 'Deduction reinstated.']);
    }

    public function showSettings()
    {
        $s = $this->attendanceService->settings();
        return response()->json(['data' => $s]);
    }

    public function updateSettings(Request $request)
    {
        $this->authorizePermission('staff_reports.review');
        $data = $request->validate([
            'check_in_time'       => 'required|date_format:H:i',
            'check_out_time'      => 'required|date_format:H:i',
            'penalties_enabled'   => 'boolean',
            'penalty_absent'      => 'nullable|numeric|min:0',
            'penalty_late'        => 'nullable|numeric|min:0',
            'penalty_left_early'  => 'nullable|numeric|min:0',
            'penalty_no_checkout' => 'nullable|numeric|min:0',
            'working_days'        => 'nullable|array',
            'working_days.*'      => 'integer|min:1|max:7',
        ]);
        $s = $this->attendanceService->settings();
        $s->update($data);
        return response()->json(['data' => $s]);
    }

    // ---------------------------------------------------------------------
    // Self-service geofenced check-in/out — no vendor device, no clerk.
    // Needs no permission beyond being signed in: every staff member checks
    // themselves in, same spirit as mine() above.
    // ---------------------------------------------------------------------

    /**
     * A staff member's own check-in from the app: confirms they're within
     * their assigned work location's radius, and that the phone doing the
     * check-in is the one already bound to their account (the first
     * check-in ever binds it; see resetDevice() for what happens when they
     * get a new phone).
     */
    public function checkIn(Request $request)
    {
        $data = $request->validate([
            'latitude' => 'required|numeric|between:-90,90',
            'longitude' => 'required|numeric|between:-180,180',
            'device_id' => 'required|string|max:255',
            'device_model' => 'nullable|string|max:255',
        ]);

        $user = auth()->user();

        $deviceError = $this->checkDevice($user, $data['device_id'], $data['device_model'] ?? null);
        if ($deviceError) {
            return $deviceError;
        }

        $locationError = $this->checkWithinWorkLocation($user, $data['latitude'], $data['longitude']);
        if ($locationError) {
            return $locationError;
        }

        $today = now()->toDateString();
        $att = Attendance::firstOrNew(['user_id' => $user->id, 'date' => $today]);
        if ($att->exists && $att->check_in_at) {
            return response()->json(['message' => 'You have already checked in today.'], 422);
        }

        $att->tenant_id ??= $user->tenant_id;
        $att->check_in_at = now();
        $att->save();

        $f = $this->attendanceService->formatDay($att, $this->attendanceService->settings());
        return response()->json(['data' => $f]);
    }

    /** The other half of checkIn() — same device/location checks. */
    public function checkOut(Request $request)
    {
        $data = $request->validate([
            'latitude' => 'required|numeric|between:-90,90',
            'longitude' => 'required|numeric|between:-180,180',
            'device_id' => 'required|string|max:255',
        ]);

        $user = auth()->user();

        $deviceError = $this->checkDevice($user, $data['device_id'], null, allowBinding: false);
        if ($deviceError) {
            return $deviceError;
        }

        $locationError = $this->checkWithinWorkLocation($user, $data['latitude'], $data['longitude']);
        if ($locationError) {
            return $locationError;
        }

        $today = now()->toDateString();
        $att = Attendance::where('user_id', $user->id)->whereDate('date', $today)->first();
        if (!$att || !$att->check_in_at) {
            return response()->json(['message' => 'You have not checked in today yet.'], 422);
        }
        if ($att->check_out_at) {
            return response()->json(['message' => 'You have already checked out today.'], 422);
        }

        $att->check_out_at = now();
        $att->save();

        $f = $this->attendanceService->formatDay($att, $this->attendanceService->settings());
        return response()->json(['data' => $f]);
    }

    /**
     * An admin clearing a staff member's device binding — the only way
     * back in once they've lost or replaced the phone that was bound.
     * Needs `attendance.manage`, same gate as every other clerk action here.
     */
    public function resetDevice(User $user)
    {
        $this->authorizePermission('attendance.manage');

        $user->attendance_device_id = null;
        $user->attendance_device_model = null;
        $user->attendance_device_bound_at = null;
        $user->save();

        return response()->json(['message' => 'Device binding cleared. They can check in again from a new phone.']);
    }

    /**
     * First check-in ever binds the phone; every one after must match it.
     * [$allowBinding] is false on checkout — a device that never checked in
     * has no business checking out either way.
     */
    private function checkDevice(User $user, string $deviceId, ?string $deviceModel, bool $allowBinding = true)
    {
        if ($user->attendance_device_id === null) {
            if (!$allowBinding) {
                return response()->json(['message' => 'You have not checked in today yet.'], 422);
            }
            $user->attendance_device_id = $deviceId;
            $user->attendance_device_model = $deviceModel;
            $user->attendance_device_bound_at = now();
            $user->save();
            return null;
        }

        if ($user->attendance_device_id !== $deviceId) {
            return response()->json([
                'message' => 'This device is not registered to your account. Ask an administrator to reset your device to sign in from a new phone.',
                'code' => 'DEVICE_NOT_REGISTERED',
            ], 403);
        }

        return null;
    }

    private function checkWithinWorkLocation(User $user, float $latitude, float $longitude)
    {
        $location = $user->work_location_id ? WorkLocation::find($user->work_location_id) : null;
        if (!$location || !$location->is_active) {
            return response()->json([
                'message' => 'You are not assigned an active work location. Contact your administrator.',
            ], 422);
        }

        $distance = $location->distanceMetersTo($latitude, $longitude);
        if ($distance > $location->radius_meters) {
            return response()->json([
                'message' => sprintf(
                    'You are %dm away from %s — you must be within %dm to check in/out.',
                    round($distance),
                    $location->name,
                    $location->radius_meters
                ),
                'code' => 'OUTSIDE_WORK_LOCATION',
                'distance_meters' => round($distance),
            ], 422);
        }

        return null;
    }

    // formatDay()/settings() moved to AttendanceService — shared with
    // LeaveRequestController via AttendanceService::markExcused().
}

<?php

namespace App\Http\Controllers;

use App\Models\Attendance;
use App\Models\AttendancePenalty;
use App\Models\AttendanceSettings;
use App\Models\User;
use App\Traits\AuthorizesPermissions;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class AttendanceController extends Controller
{
    use AuthorizesPermissions;

    /** Personal dashboard: today's status + this month's summary & deductions. */
    public function mine()
    {
        $user = auth()->user();
        $s    = $this->settings();
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
            'today' => $today ? $this->formatDay($today, $s) : null,
            'month_label'   => now()->format('M Y'),
            'present_days'  => $records->whereNotNull('check_in_at')->count(),
            'month_records' => $records->map(fn ($a) => $this->formatDay($a, $s))->values(),
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
        $s = $this->settings();

        $users = User::where('tenant_id', auth()->user()->tenant_id)
            ->where('is_active', true)->orderBy('name')->get(['id', 'name']);
        $records = Attendance::whereDate('date', $date)->get()->keyBy('user_id');

        $staff = $users->map(function ($u) use ($records, $s, $date) {
            $att = $records->get($u->id);
            $day = $att ? $this->formatDay($att, $s) : [
                'date' => $date, 'check_in_at' => null, 'check_out_at' => null,
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
            'user_id'   => ['required', Rule::exists('users', 'id')->where('tenant_id', $tenantId)],
            'date'      => 'required|date',
            'check_in'  => 'nullable|date_format:H:i',
            'check_out' => 'nullable|date_format:H:i',
        ]);

        $date = Carbon::parse($data['date']);
        $att = Attendance::firstOrNew(['user_id' => $data['user_id'], 'date' => $date->toDateString()]);
        $att->tenant_id ??= $tenantId;
        $att->check_in_at  = !empty($data['check_in'])  ? $date->copy()->setTimeFromTimeString($data['check_in'])  : null;
        $att->check_out_at = !empty($data['check_out']) ? $date->copy()->setTimeFromTimeString($data['check_out']) : null;
        $att->save();

        return response()->json(['data' => ['user' => ['id' => $att->user_id]] + $this->formatDay($att, $this->settings())]);
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
        $s = $this->settings();
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
        $s = $this->settings();
        $s->update($data);
        return response()->json(['data' => $s]);
    }

    /** Status flags for a day, evaluated against the settings' times. */
    private function formatDay(Attendance $a, AttendanceSettings $s): array
    {
        $late = $a->check_in_at
            && $a->check_in_at->gt($a->date->copy()->setTimeFromTimeString($s->check_in_time));
        $leftEarly = $a->check_out_at
            && $a->check_out_at->lt($a->date->copy()->setTimeFromTimeString($s->check_out_time));

        return [
            'id'           => $a->id,
            'date'         => $a->date->format('Y-m-d'),
            'check_in_at'  => $a->check_in_at?->format('H:i'),
            'check_out_at' => $a->check_out_at?->format('H:i'),
            'absent'       => !$a->check_in_at,          // no check-in = absent (even if checked out)
            'late'         => (bool) $late,
            'left_early'   => (bool) $leftEarly,
            'no_checkout'  => $a->check_in_at && !$a->check_out_at,
        ];
    }

    private function settings(): AttendanceSettings
    {
        return AttendanceSettings::firstOrCreate([], [
            'check_in_time'  => '07:30',
            'check_out_time' => '17:00',
            'penalties_enabled'   => true,
            'penalty_absent'      => 5000,
            'penalty_late'        => 2000,
            'penalty_left_early'  => 2000,
            'penalty_no_checkout' => 2000,
            'working_days'        => [1, 2, 3, 4, 5, 6],
        ]);
    }
}

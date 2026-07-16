<?php

namespace App\Http\Controllers;

use App\Models\Attendance;
use App\Models\AttendancePenalty;
use App\Models\AttendanceSettings;
use App\Traits\AuthorizesPermissions;
use Carbon\Carbon;
use Illuminate\Http\Request;

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
            'deductions' => $penalties->map(fn ($p) => [
                'id'   => $p->id,
                'date' => $p->date->format('Y-m-d'),
                'penalty_type' => $p->penalty_type,
                'amount' => round((float) $p->amount, 2),
                'notes'  => $p->notes,
            ])->values(),
        ]]);
    }

    public function checkIn(Request $request)
    {
        return $this->mark($request, 'in');
    }

    public function checkOut(Request $request)
    {
        return $this->mark($request, 'out');
    }

    private function mark(Request $request, string $which)
    {
        $user = auth()->user();
        $data = $request->validate(['time' => 'nullable|date_format:H:i']);

        $now = $data['time']
            ? now()->setTimeFromTimeString($data['time'])
            : now();
        $date = now()->toDateString();

        $att = Attendance::firstOrNew(['user_id' => $user->id, 'date' => $date]);
        $att->tenant_id ??= $user->tenant_id;

        if ($which === 'in') {
            if ($att->check_in_at) {
                return response()->json(['message' => 'You already checked in today at ' . $att->check_in_at->format('H:i') . '.'], 422);
            }
            $att->check_in_at = $now;
        } else {
            if ($att->check_out_at) {
                return response()->json(['message' => 'You already checked out today at ' . $att->check_out_at->format('H:i') . '.'], 422);
            }
            $att->check_out_at = $now;
        }
        $att->save();

        return response()->json(['data' => $this->formatDay($att, $this->settings())]);
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

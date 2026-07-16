<?php

namespace App\Http\Controllers;

use App\Models\StaffReportHoliday;
use App\Models\StaffReportPenalty;
use App\Models\StaffReportSettings;
use App\Traits\AuthorizesPermissions;
use Illuminate\Http\Request;

class StaffReportSettingsController extends Controller
{
    use AuthorizesPermissions;

    /** Holidays (office-closed days) — staff can view, reviewers manage. */
    public function holidays()
    {
        $this->authorizePermission('staff_reports.submit');
        return response()->json(['data' => StaffReportHoliday::orderBy('date')->get()]);
    }

    public function storeHoliday(Request $request)
    {
        $this->authorizePermission('staff_reports.review');
        $data = $request->validate([
            'date' => 'required|date',
            'name' => 'nullable|string|max:255',
        ]);

        $holiday = StaffReportHoliday::updateOrCreate(
            ['date' => $data['date']],
            ['name' => $data['name'] ?? null],
        );

        // Undo any daily missing-deductions already charged for that day.
        StaffReportPenalty::where('report_type', 'daily')
            ->where('penalty_type', 'missing')
            ->whereDate('period_date', $data['date'])
            ->delete();

        return response()->json(['data' => $holiday], 201);
    }

    public function destroyHoliday(StaffReportHoliday $holiday)
    {
        $this->authorizePermission('staff_reports.review');
        $holiday->delete();
        return response()->json(null, 204);
    }

    public function show()
    {
        $this->authorizePermission('staff_reports.submit');
        return response()->json(['data' => $this->settings()]);
    }

    public function update(Request $request)
    {
        $this->authorizePermission('staff_reports.review');

        $data = $request->validate([
            'daily_target'          => 'required|integer|min:1|max:200',
            'weekly_target'         => 'required|integer|min:1|max:50',
            'monthly_target'        => 'required|integer|min:1|max:12',
            'daily_deadline_time'   => 'required|date_format:H:i',
            'weekly_deadline_day'   => 'required|integer|min:1|max:7',
            'weekly_deadline_time'  => 'required|date_format:H:i',
            'monthly_deadline_day'  => 'required|integer|min:1|max:28',
            'monthly_deadline_time' => 'required|date_format:H:i',
            'penalties_enabled'       => 'boolean',
            'penalty_missing_daily'   => 'nullable|numeric|min:0',
            'penalty_late'            => 'nullable|numeric|min:0',
            'penalty_missing_weekly'  => 'nullable|numeric|min:0',
            'penalty_missing_monthly' => 'nullable|numeric|min:0',
        ]);

        $settings = $this->settings();
        $settings->update($data);

        return response()->json(['data' => $settings]);
    }

    private function settings(): StaffReportSettings
    {
        return StaffReportSettings::firstOrCreate([], [
            'daily_target'          => 20,
            'weekly_target'         => 4,
            'monthly_target'        => 1,
            'daily_deadline_time'   => '18:00',
            'weekly_deadline_day'   => 5,
            'weekly_deadline_time'  => '17:00',
            'monthly_deadline_day'  => 28,
            'monthly_deadline_time' => '17:00',
            'penalties_enabled'       => true,
            'penalty_missing_daily'   => 5000,
            'penalty_late'            => 2000,
            'penalty_missing_weekly'  => 7000,
            'penalty_missing_monthly' => 10000,
        ]);
    }
}
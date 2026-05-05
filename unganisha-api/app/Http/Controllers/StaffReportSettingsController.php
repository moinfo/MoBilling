<?php

namespace App\Http\Controllers;

use App\Models\StaffReportSettings;
use App\Traits\AuthorizesPermissions;
use Illuminate\Http\Request;

class StaffReportSettingsController extends Controller
{
    use AuthorizesPermissions;

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
        ]);
    }
}
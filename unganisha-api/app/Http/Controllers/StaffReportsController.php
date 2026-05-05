<?php

namespace App\Http\Controllers;

use App\Models\StaffReport;
use App\Traits\AuthorizesPermissions;
use Carbon\Carbon;
use Illuminate\Http\Request;

class StaffReportsController extends Controller
{
    use AuthorizesPermissions;

    public function index(Request $request)
    {
        $this->authorizePermission('staff_reports.submit');

        $user  = auth()->user();
        $query = StaffReport::with(['user', 'reviewer'])
            ->orderBy('period_date', 'desc')
            ->orderBy('created_at', 'desc');

        if (!$user->hasPermission('staff_reports.review')) {
            $query->where('user_id', $user->id);
        }

        if ($request->report_type) $query->where('report_type', $request->report_type);
        if ($request->user_id)     $query->where('user_id', $request->user_id);
        if ($request->status)      $query->where('status', $request->status);

        return response()->json(['data' => $query->get()->map(fn ($r) => $this->format($r))]);
    }

    public function store(Request $request)
    {
        $this->authorizePermission('staff_reports.submit');

        $data = $request->validate([
            'report_type'  => 'required|in:daily,weekly,monthly',
            'period_date'  => 'required|date',
            'achievements' => 'nullable|string|max:5000',
            'challenges'   => 'nullable|string|max:5000',
            'plans'        => 'nullable|string|max:5000',
            'notes'        => 'nullable|string|max:2000',
        ]);

        $data['period_date'] = $this->normalizePeriod($data['report_type'], $data['period_date']);
        $data['user_id']     = auth()->id();

        $exists = StaffReport::where('user_id', $data['user_id'])
            ->where('report_type', $data['report_type'])
            ->where('period_date', $data['period_date'])
            ->exists();

        if ($exists) {
            $label = $this->periodLabel($data['report_type'], Carbon::parse($data['period_date']));
            return response()->json([
                'message' => "You already submitted a {$data['report_type']} report for {$label}.",
                'errors'  => ['period_date' => ['Duplicate: a report already exists for this period.']],
            ], 422);
        }

        $report = StaffReport::create($data);
        return response()->json(['data' => $this->format($report->load(['user', 'reviewer']))], 201);
    }

    public function update(Request $request, StaffReport $staffReport)
    {
        $this->authorizePermission('staff_reports.submit');

        if ($staffReport->user_id !== auth()->id()) {
            abort(403, 'You can only edit your own reports.');
        }
        if ($staffReport->status === 'reviewed') {
            abort(422, 'Cannot edit a report that has already been reviewed.');
        }

        $data = $request->validate([
            'achievements' => 'nullable|string|max:5000',
            'challenges'   => 'nullable|string|max:5000',
            'plans'        => 'nullable|string|max:5000',
            'notes'        => 'nullable|string|max:2000',
        ]);

        $staffReport->update($data);
        return response()->json(['data' => $this->format($staffReport->load(['user', 'reviewer']))]);
    }

    public function destroy(StaffReport $staffReport)
    {
        $this->authorizePermission('staff_reports.submit');

        if ($staffReport->user_id !== auth()->id()) {
            abort(403);
        }
        if ($staffReport->status === 'reviewed') {
            abort(422, 'Cannot delete a reviewed report.');
        }

        $staffReport->delete();
        return response()->json(null, 204);
    }

    public function review(Request $request, StaffReport $staffReport)
    {
        $this->authorizePermission('staff_reports.review');

        $data = $request->validate([
            'rating'       => 'nullable|integer|min:1|max:5',
            'review_notes' => 'nullable|string|max:3000',
        ]);

        $staffReport->update([
            'status'       => 'reviewed',
            'reviewed_by'  => auth()->id(),
            'reviewed_at'  => now(),
            'rating'       => $data['rating'] ?? null,
            'review_notes' => $data['review_notes'] ?? null,
        ]);

        return response()->json(['data' => $this->format($staffReport->load(['user', 'reviewer']))]);
    }

    private function normalizePeriod(string $type, string $date): string
    {
        $carbon = Carbon::parse($date);
        return match ($type) {
            'daily'   => $carbon->toDateString(),
            'weekly'  => $carbon->startOfWeek(Carbon::MONDAY)->toDateString(),
            'monthly' => $carbon->startOfMonth()->toDateString(),
        };
    }

    private function periodLabel(string $type, Carbon $date): string
    {
        return match ($type) {
            'daily'   => $date->format('D, j M Y'),
            'weekly'  => 'Week ' . $date->isoWeek() . ' · ' . $date->format('j M') . '–' . $date->copy()->addDays(6)->format('j M Y'),
            'monthly' => $date->format('M Y'),
        };
    }

    private function format(StaffReport $r): array
    {
        return [
            'id'           => $r->id,
            'user'         => ['id' => $r->user->id, 'name' => $r->user->name],
            'report_type'  => $r->report_type,
            'period_date'  => $r->period_date->toDateString(),
            'period_label' => $this->periodLabel($r->report_type, $r->period_date),
            'achievements' => $r->achievements,
            'challenges'   => $r->challenges,
            'plans'        => $r->plans,
            'notes'        => $r->notes,
            'status'       => $r->status,
            'reviewer'     => $r->reviewer ? ['id' => $r->reviewer->id, 'name' => $r->reviewer->name] : null,
            'reviewed_at'  => $r->reviewed_at?->toISOString(),
            'review_notes' => $r->review_notes,
            'rating'       => $r->rating,
            'created_at'   => $r->created_at->toISOString(),
        ];
    }
}

<?php

namespace App\Http\Controllers;

use App\Models\StaffReport;
use App\Models\StaffReportSettings;
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

        if ($user->hasPermission('staff_reports.view_all')) {
            // see all reports in the tenant (no extra filter)
        } elseif ($user->hasPermission('staff_reports.review')) {
            // see only assigned subordinates' reports (plus own)
            $subordinateIds = \App\Models\User::where('tenant_id', $user->tenant_id)
                ->where('supervisor_id', $user->id)
                ->pluck('id')
                ->push($user->id);
            $query->whereIn('user_id', $subordinateIds);
        } else {
            // own reports only
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
        $data['is_late']     = $this->isLate($data['report_type'], $data['period_date']);

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

    public function dashboard()
    {
        $this->authorizePermission('staff_reports.submit');

        $user     = auth()->user();
        $settings = $this->getSettings();
        $now      = now();
        $monthStart = $now->copy()->startOfMonth()->toDateString();
        $monthEnd   = $now->copy()->endOfMonth()->toDateString();

        // My own stats for this month
        $thisMonth = [];
        foreach (['daily', 'weekly', 'monthly'] as $type) {
            $base = StaffReport::where('user_id', $user->id)
                ->where('report_type', $type)
                ->whereBetween('period_date', [$monthStart, $monthEnd]);

            $submitted = (clone $base)->count();
            $reviewed  = (clone $base)->where('status', 'reviewed')->count();
            $late      = (clone $base)->where('is_late', true)->count();
            $target    = match ($type) {
                'daily'   => $settings->daily_target,
                'weekly'  => $settings->weekly_target,
                'monthly' => $settings->monthly_target,
            };

            $thisMonth[$type] = compact('submitted', 'reviewed', 'late', 'target');
        }

        $recentReviews = StaffReport::with(['reviewer'])
            ->where('user_id', $user->id)
            ->where('status', 'reviewed')
            ->orderBy('reviewed_at', 'desc')
            ->take(5)
            ->get()
            ->map(fn ($r) => $this->format($r));

        // Team-wide stats (supervisors + view_all)
        $team = null;
        if ($user->hasPermission('staff_reports.review') || $user->hasPermission('staff_reports.view_all')) {
            // Determine which users to show
            if ($user->hasPermission('staff_reports.view_all')) {
                $visibleUsers = \App\Models\User::where('tenant_id', $user->tenant_id)
                    ->orderBy('name')
                    ->get(['id', 'name']);
            } else {
                // Supervisor: only their assigned subordinates
                $visibleUsers = \App\Models\User::where('tenant_id', $user->tenant_id)
                    ->where('supervisor_id', $user->id)
                    ->orderBy('name')
                    ->get(['id', 'name']);
            }

            $visibleIds   = $visibleUsers->pluck('id');
            $pendingReview = StaffReport::whereIn('user_id', $visibleIds)
                ->where('status', 'submitted')
                ->count();

            // Load this month's reports for visible staff in one query
            $monthReports = StaffReport::with('user')
                ->whereIn('user_id', $visibleIds)
                ->whereBetween('period_date', [$monthStart, $monthEnd])
                ->get()
                ->groupBy('user_id');

            $targets = [
                'daily'   => $settings->daily_target,
                'weekly'  => $settings->weekly_target,
                'monthly' => $settings->monthly_target,
            ];

            $staffStats = $visibleUsers->map(function ($u) use ($monthReports, $targets) {
                $reports = $monthReports->get($u->id, collect());
                $row     = ['user' => ['id' => $u->id, 'name' => $u->name]];
                foreach (['daily', 'weekly', 'monthly'] as $type) {
                    $tr = $reports->where('report_type', $type);
                    $row[$type] = [
                        'submitted' => $tr->count(),
                        'reviewed'  => $tr->where('status', 'reviewed')->count(),
                        'late'      => $tr->where('is_late', true)->count(),
                        'target'    => $targets[$type],
                    ];
                }
                return $row;
            });

            $team = [
                'pending_review' => $pendingReview,
                'staff'          => $staffStats->values()->all(),
            ];
        }

        return response()->json([
            'data' => [
                'this_month'     => $thisMonth,
                'recent_reviews' => $recentReviews,
                'settings'       => $settings,
                'team'           => $team,
            ],
        ]);
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private function isLate(string $type, string $periodDate): bool
    {
        $s   = $this->getSettings();
        $now = now();

        $deadline = match ($type) {
            'daily'   => Carbon::parse($periodDate)
                ->setTimeFromTimeString($s->daily_deadline_time),
            'weekly'  => Carbon::parse($periodDate)
                ->addDays($s->weekly_deadline_day - 1)
                ->setTimeFromTimeString($s->weekly_deadline_time),
            'monthly' => Carbon::parse($periodDate)
                ->addDays($s->monthly_deadline_day - 1)
                ->setTimeFromTimeString($s->monthly_deadline_time),
        };

        return $now->gt($deadline);
    }

    private function getSettings(): StaffReportSettings
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
            'is_late'      => (bool) $r->is_late,
            'reviewer'     => $r->reviewer ? ['id' => $r->reviewer->id, 'name' => $r->reviewer->name] : null,
            'reviewed_at'  => $r->reviewed_at?->toISOString(),
            'review_notes' => $r->review_notes,
            'rating'       => $r->rating,
            'created_at'   => $r->created_at->toISOString(),
        ];
    }
}
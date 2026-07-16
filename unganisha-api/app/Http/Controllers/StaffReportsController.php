<?php

namespace App\Http\Controllers;

use App\Models\StaffReport;
use App\Models\StaffReportSettings;
use App\Notifications\StaffReportReviewedNotification;
use App\Notifications\StaffReportSubmittedNotification;
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
        $query = StaffReport::with(['user', 'reviewer', 'replies'])
            // hide reports belonging to deactivated/inactive staff
            ->whereHas('user', fn ($q) => $q->where('is_active', true))
            ->orderBy('period_date', 'desc')
            ->orderBy('created_at', 'desc');

        if ($user->hasPermission('staff_reports.view_all')) {
            // see all reports in the tenant (no extra filter)
        } elseif ($user->hasPermission('staff_reports.review')) {
            // see only assigned subordinates' reports (plus own)
            $subordinateIds = \App\Models\User::where('tenant_id', $user->tenant_id)
                ->where('supervisor_id', $user->id)
                ->where('is_active', true)
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
        $report->load(['user', 'reviewer', 'replies']);

        // Late submission → record the late-report deduction (once per period).
        if ($report->is_late) {
            $s = $this->getSettings();
            if ($s->penalties_enabled && (float) $s->penalty_late > 0) {
                \App\Models\StaffReportPenalty::firstOrCreate(
                    [
                        'user_id'      => $report->user_id,
                        'report_type'  => $report->report_type,
                        'penalty_type' => 'late',
                        'period_date'  => $report->period_date->toDateString(),
                    ],
                    [
                        'tenant_id'       => $report->tenant_id,
                        'amount'          => $s->penalty_late,
                        'staff_report_id' => $report->id,
                        'notes'           => 'Late ' . $report->report_type . ' report',
                    ],
                );
            }
        }

        // Notify supervisor of the new submission
        $supervisor = $report->user->supervisor;
        if ($supervisor) {
            $supervisor->notify(new StaffReportSubmittedNotification($report->user->tenant, $report));
        }

        return response()->json(['data' => $this->format($report)], 201);
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
        if ($this->periodEnded($staffReport)) {
            abort(422, 'This report is locked — you can only edit it on the day it covers.');
        }

        $data = $request->validate([
            'achievements' => 'nullable|string|max:5000',
            'challenges'   => 'nullable|string|max:5000',
            'plans'        => 'nullable|string|max:5000',
            'notes'        => 'nullable|string|max:2000',
        ]);

        $staffReport->update($data);
        return response()->json(['data' => $this->format($staffReport->load(['user', 'reviewer', 'replies']))]);
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
        if ($this->periodEnded($staffReport)) {
            abort(422, 'This report is locked — you can only delete it on the day it covers.');
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

        $staffReport->load(['user', 'reviewer', 'replies']);

        // Notify the staff member that their report was reviewed
        $staffReport->user->notify(
            new StaffReportReviewedNotification($staffReport->user->tenant, $staffReport)
        );

        return response()->json(['data' => $this->format($staffReport)]);
    }

    /** Supervisor/admin view of everyone's deductions for a month. */
    public function penalties(Request $request)
    {
        $this->authorizePermission('staff_reports.review');
        $user = auth()->user();

        $month = (int) $request->query('month', now()->month);
        $year  = (int) $request->query('year', now()->year);
        $start = Carbon::createFromDate($year, $month, 1)->startOfMonth();
        $end   = $start->copy()->endOfMonth();

        $userIds = $this->penaltyScopeUserIds($user);

        $rows = \App\Models\StaffReportPenalty::with('user:id,name')
            ->whereIn('user_id', $userIds)
            ->whereBetween('period_date', [$start->toDateString(), $end->toDateString()])
            ->orderByDesc('period_date')->orderByDesc('created_at')
            ->get();

        $staff = $rows->groupBy('user_id')->map(function ($rs) {
            $active = $rs->where('waived', false);
            return [
                'user'  => ['id' => $rs->first()->user_id, 'name' => $rs->first()->user?->name ?? 'Unknown'],
                'total' => round((float) $active->sum('amount'), 2),
                'count' => $active->count(),
                'by_type' => collect(['daily', 'weekly', 'monthly'])->mapWithKeys(fn ($t) => [
                    $t => (int) $active->where('report_type', $t)->count(),
                ]),
                'late'  => (int) $active->where('penalty_type', 'late')->count(),
                'items' => $rs->map(fn ($p) => [
                    'id'           => $p->id,
                    'report_type'  => $p->report_type,
                    'penalty_type' => $p->penalty_type,
                    'period_date'  => $p->period_date->format('Y-m-d'),
                    'amount'       => round((float) $p->amount, 2),
                    'notes'        => $p->notes,
                    'waived'       => (bool) $p->waived,
                    'waive_reason' => $p->waive_reason,
                ])->values(),
            ];
        })->sortByDesc('total')->values();

        return response()->json(['data' => [
            'month_label' => $start->format('M Y'),
            'grand_total' => round((float) $rows->where('waived', false)->sum('amount'), 2),
            'staff'       => $staff,
        ]]);
    }

    public function waivePenalty(Request $request, \App\Models\StaffReportPenalty $staffReportPenalty)
    {
        $this->authorizePermission('staff_reports.review');
        $this->assertPenaltyInScope($staffReportPenalty);

        $data = $request->validate(['reason' => 'nullable|string|max:255']);
        $staffReportPenalty->update([
            'waived'       => true,
            'waived_by'    => auth()->id(),
            'waived_at'    => now(),
            'waive_reason' => $data['reason'] ?? null,
        ]);

        return response()->json(['message' => 'Deduction waived.']);
    }

    public function unwaivePenalty(\App\Models\StaffReportPenalty $staffReportPenalty)
    {
        $this->authorizePermission('staff_reports.review');
        $this->assertPenaltyInScope($staffReportPenalty);

        $staffReportPenalty->update([
            'waived' => false, 'waived_by' => null, 'waived_at' => null, 'waive_reason' => null,
        ]);

        return response()->json(['message' => 'Deduction reinstated.']);
    }

    /** Users whose deductions this reviewer may see (all, or their subordinates). */
    private function penaltyScopeUserIds($user)
    {
        if ($user->hasPermission('staff_reports.view_all')) {
            return \App\Models\User::where('tenant_id', $user->tenant_id)->pluck('id');
        }
        return \App\Models\User::where('tenant_id', $user->tenant_id)
            ->where('supervisor_id', $user->id)->pluck('id');
    }

    private function assertPenaltyInScope(\App\Models\StaffReportPenalty $p): void
    {
        abort_unless($this->penaltyScopeUserIds(auth()->user())->contains($p->user_id), 403);
    }

    /**
     * Add a reply to a report's feedback thread. The report owner (staff) can
     * respond to a supervisor's review; a supervisor can reply back. Emails the
     * other party (gated by the tenant's email settings).
     */
    public function reply(Request $request, StaffReport $staffReport)
    {
        $author   = auth()->user();
        $isOwner  = $staffReport->user_id === $author->id;
        $canReview = $author->hasPermission('staff_reports.review');
        abort_unless($isOwner || $canReview, 403, 'You cannot reply to this report.');

        $data = $request->validate(['message' => 'required|string|max:3000']);

        $reply = \App\Models\StaffReportReply::create([
            'tenant_id'       => $staffReport->tenant_id,
            'staff_report_id' => $staffReport->id,
            'user_id'         => $author->id,
            'message'         => $data['message'],
        ]);

        // Notify the other party: staff→supervisor(reviewer/supervisor), supervisor→staff.
        $recipient = $isOwner
            ? ($staffReport->reviewer ?? $staffReport->user->supervisor)
            : $staffReport->user;

        if ($recipient && $recipient->id !== $author->id) {
            $recipient->notify(new \App\Notifications\StaffReportReplyNotification(
                $author->tenant, $staffReport, $reply, $author->name
            ));
        }

        return response()->json(['data' => $this->format($staffReport->fresh(['user', 'reviewer', 'replies']))], 201);
    }

    public function dashboard()
    {
        $this->authorizePermission('staff_reports.submit');

        $user     = auth()->user();
        $settings = $this->getSettings();
        $now      = now();
        $monthStart = $now->copy()->startOfMonth()->toDateString();
        $monthEnd   = $now->copy()->endOfMonth()->toDateString();

        // Office-closed days this tenant (skip for the daily expected count)
        $holidays = \App\Models\StaffReportHoliday::pluck('date')->map(fn ($d) => $d->toDateString())->all();

        // My own stats for this month
        $thisMonth = [];
        foreach (['daily', 'weekly', 'monthly'] as $type) {
            $base = StaffReport::where('user_id', $user->id)
                ->where('report_type', $type)
                ->whereBetween('period_date', [$monthStart, $monthEnd]);

            $submitted = (clone $base)->count();
            $reviewed  = (clone $base)->where('status', 'reviewed')->count();
            $late      = (clone $base)->where('is_late', true)->count();
            // Targets reflect the actual month: Mon–Sat working days (minus
            // holidays) for daily, and the number of weeks for weekly.
            $target    = match ($type) {
                'daily'   => $this->workingDaysInMonth($now, $settings, $holidays),
                'weekly'  => $this->weeksInMonth($settings, $now),
                'monthly' => $settings->monthly_target,
            };
            // How many are actually due by today (elapsed weekdays/weeks past deadline)
            if ($type === 'weekly') {
                // Count coverage per due week (matches the deduction logic) so a
                // month-straddling first-week report isn't missed by the month filter.
                [$expected, $submitted, $missing] = $this->weeklyProgress($user->id, $settings, $now);
            } else {
                $expected = $this->expectedSoFar($type, $settings, $now, $holidays);
                $missing  = max(0, $expected - $submitted);
            }

            $thisMonth[$type] = compact('submitted', 'reviewed', 'late', 'target', 'expected', 'missing');
        }

        $recentReviews = StaffReport::with(['reviewer', 'replies'])
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
                    ->where('is_active', true)
                    ->orderBy('name')
                    ->get(['id', 'name']);
            } else {
                // Supervisor: only their assigned subordinates
                $visibleUsers = \App\Models\User::where('tenant_id', $user->tenant_id)
                    ->where('supervisor_id', $user->id)
                    ->where('is_active', true)
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

            // Same auto-calculated targets as the personal cards
            $targets = [
                'daily'   => $this->workingDaysInMonth($now, $settings, $holidays),
                'weekly'  => $this->weeksInMonth($settings, $now),
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

    /**
     * Weekly progress by DUE WEEK (deadline in month, passed): returns
     * [expected, covered, missing], checking coverage by each week's Monday so
     * a report for the month-straddling first week counts even though its
     * period_date is in the previous month. Consistent with the deductions.
     */
    private function weeklyProgress(string $userId, StaffReportSettings $s, Carbon $now): array
    {
        $monthStart = $now->copy()->startOfMonth();
        $monthEnd   = $now->copy()->endOfMonth();
        $expected = 0;
        $covered  = 0;

        for ($w = $monthStart->copy()->startOfWeek(Carbon::MONDAY); $w->lte($now); $w->addWeek()) {
            $deadline = $w->copy()->addDays($s->weekly_deadline_day - 1)->setTimeFromTimeString($s->weekly_deadline_time);
            if ($deadline->lt($monthStart) || $deadline->gt($monthEnd) || !$now->gt($deadline)) {
                continue;
            }
            $expected++;
            $has = StaffReport::where('user_id', $userId)
                ->where('report_type', 'weekly')
                ->whereDate('period_date', $w->toDateString())
                ->exists();
            if ($has) {
                $covered++;
            }
        }

        return [$expected, $covered, max(0, $expected - $covered)];
    }

    /** Working days in the month (per the configured week), minus holidays. */
    private function workingDaysInMonth(Carbon $now, StaffReportSettings $s, array $holidays = []): int
    {
        $workDays = $s->working_days ?: [1, 2, 3, 4, 5, 6];
        $c = 0;
        $end = $now->copy()->endOfMonth();
        for ($d = $now->copy()->startOfMonth(); $d->lte($end); $d->addDay()) {
            if (in_array($d->dayOfWeekIso, $workDays) && !in_array($d->toDateString(), $holidays, true)) {
                $c++;
            }
        }
        return $c;
    }

    /** Number of weeks in the month (weeks whose deadline falls in it). */
    private function weeksInMonth(StaffReportSettings $s, Carbon $now): int
    {
        $c = 0;
        $monthStart = $now->copy()->startOfMonth();
        $monthEnd   = $now->copy()->endOfMonth();
        for ($w = $monthStart->copy()->startOfWeek(Carbon::MONDAY); $w->lte($monthEnd); $w->addWeek()) {
            $deadline = $w->copy()->addDays($s->weekly_deadline_day - 1)->setTimeFromTimeString($s->weekly_deadline_time);
            if ($deadline->gte($monthStart) && $deadline->lte($monthEnd)) {
                $c++;
            }
        }
        return $c;
    }

    /** How many reports of a type are DUE by now this month (deadline passed). */
    private function expectedSoFar(string $type, StaffReportSettings $s, Carbon $now, array $holidays = []): int
    {
        $monthStart = $now->copy()->startOfMonth();

        if ($type === 'daily') {
            $workDays = $s->working_days ?: [1, 2, 3, 4, 5, 6];
            $c = 0;
            for ($d = $monthStart->copy(); $d->lte($now); $d->addDay()) {
                if (in_array($d->dayOfWeekIso, $workDays)
                    && !in_array($d->toDateString(), $holidays, true)
                    && $now->gt($d->copy()->setTimeFromTimeString($s->daily_deadline_time))) {
                    $c++;
                }
            }
            return $c;
        }

        if ($type === 'weekly') {
            // A week counts for this month if its DEADLINE falls in the month
            // and has passed (so the first, month-straddling week is included).
            $c = 0;
            $monthEnd = $now->copy()->endOfMonth();
            for ($w = $monthStart->copy()->startOfWeek(Carbon::MONDAY); $w->lte($now); $w->addWeek()) {
                $deadline = $w->copy()->addDays($s->weekly_deadline_day - 1)->setTimeFromTimeString($s->weekly_deadline_time);
                if ($deadline->gte($monthStart) && $deadline->lte($monthEnd) && $now->gt($deadline)) {
                    $c++;
                }
            }
            return $c;
        }

        $dueDay = min($s->monthly_deadline_day, $now->daysInMonth);
        return $now->gt($monthStart->copy()->addDays($dueDay - 1)->setTimeFromTimeString($s->monthly_deadline_time)) ? 1 : 0;
    }

    /** A report locks for edit/delete once its own day/period has passed. */
    private function periodEnded(StaffReport $r): bool
    {
        $end = match ($r->report_type) {
            'daily'   => $r->period_date->copy()->endOfDay(),
            'weekly'  => $r->period_date->copy()->endOfWeek(Carbon::SUNDAY),
            'monthly' => $r->period_date->copy()->endOfMonth(),
        };
        return now()->gt($end);
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
            'replies'      => $r->relationLoaded('replies') ? $r->replies->map(fn ($rep) => [
                'id'          => $rep->id,
                'user'        => ['id' => $rep->user_id, 'name' => $rep->user?->name ?? 'Unknown'],
                'is_reviewer' => $rep->user_id !== $r->user_id,
                'message'     => $rep->message,
                'created_at'  => $rep->created_at->toISOString(),
            ])->values() : [],
        ];
    }
}
<?php

namespace App\Http\Controllers;

use App\Models\StaffTarget;
use App\Models\StaffTargetCriterion;
use App\Models\User;
use App\Notifications\StaffTargetAssignedNotification;
use App\Notifications\StaffTargetSelfReportedNotification;
use App\Notifications\StaffTargetVerifiedNotification;
use App\Traits\AuthorizesPermissions;
use Illuminate\Http\Request;

class StaffTargetsController extends Controller
{
    use AuthorizesPermissions;

    // ── List ─────────────────────────────────────────────────────────────────

    public function index(Request $request)
    {
        $this->authorizePermission('staff_targets.submit');
        $user = auth()->user();

        $query = StaffTarget::with(['user', 'assignedBy', 'verifiedBy', 'criteria'])
            ->orderBy('period_start', 'desc')
            ->orderBy('created_at', 'desc');

        if ($user->hasPermission('staff_targets.manage') || $user->hasPermission('staff_targets.verify')) {
            // Supervisors/managers see their assigned subordinates (or all with view_all)
            if (!$user->hasPermission('staff_reports.view_all')) {
                $subordinateIds = User::where('tenant_id', $user->tenant_id)
                    ->where('supervisor_id', $user->id)
                    ->pluck('id')
                    ->push($user->id);
                $query->whereIn('user_id', $subordinateIds);
            }
        } else {
            $query->where('user_id', $user->id);
        }

        if ($request->user_id) $query->where('user_id', $request->user_id);
        if ($request->status)  $query->where('status', $request->status);

        return response()->json(['data' => $query->get()->map(fn ($t) => $this->format($t))]);
    }

    // ── Create ────────────────────────────────────────────────────────────────

    public function store(Request $request)
    {
        $this->authorizePermission('staff_targets.manage');
        $user = auth()->user();

        $data = $request->validate([
            'user_id'              => 'required|uuid',
            'title'                => 'required|string|max:255',
            'description'          => 'nullable|string|max:2000',
            'period_start'         => 'required|date',
            'period_end'           => 'required|date|after_or_equal:period_start',
            'criteria'             => 'required|array|min:1',
            'criteria.*.type'      => 'required|in:customer_count,revenue,item_sales,custom',
            'criteria.*.label'     => 'required|string|max:255',
            'criteria.*.unit'      => 'nullable|string|max:50',
            'criteria.*.goal_value'       => 'required|numeric|min:0',
            'criteria.*.commission_type'  => 'required|in:none,fixed,percentage',
            'criteria.*.commission_value' => 'nullable|numeric|min:0',
        ]);

        // Ensure target staff belongs to this tenant
        $targetUser = User::where('tenant_id', $user->tenant_id)->findOrFail($data['user_id']);

        $target = StaffTarget::create([
            'user_id'      => $targetUser->id,
            'assigned_by'  => $user->id,
            'title'        => $data['title'],
            'description'  => $data['description'] ?? null,
            'period_start' => $data['period_start'],
            'period_end'   => $data['period_end'],
        ]);

        foreach ($data['criteria'] as $c) {
            StaffTargetCriterion::create([
                'target_id'        => $target->id,
                'type'             => $c['type'],
                'label'            => $c['label'],
                'unit'             => $c['unit'] ?? $this->defaultUnit($c['type']),
                'goal_value'       => $c['goal_value'],
                'commission_type'  => $c['commission_type'],
                'commission_value' => $c['commission_value'] ?? null,
            ]);
        }

        $target->load(['user', 'assignedBy', 'criteria']);

        // Notify the assigned staff member
        $targetUser->notify(new StaffTargetAssignedNotification($targetUser->tenant, $target));

        return response()->json(['data' => $this->format($target)], 201);
    }

    // ── Update (admin edits target while still active) ────────────────────────

    public function update(Request $request, StaffTarget $staffTarget)
    {
        $this->authorizePermission('staff_targets.manage');

        if (!in_array($staffTarget->status, ['active'])) {
            abort(422, 'Only active targets can be edited.');
        }

        $data = $request->validate([
            'title'       => 'sometimes|string|max:255',
            'description' => 'nullable|string|max:2000',
            'period_start'=> 'sometimes|date',
            'period_end'  => 'sometimes|date',
            'criteria'    => 'sometimes|array|min:1',
            'criteria.*.type'             => 'required_with:criteria|in:customer_count,revenue,item_sales,custom',
            'criteria.*.label'            => 'required_with:criteria|string|max:255',
            'criteria.*.unit'             => 'nullable|string|max:50',
            'criteria.*.goal_value'       => 'required_with:criteria|numeric|min:0',
            'criteria.*.commission_type'  => 'required_with:criteria|in:none,fixed,percentage',
            'criteria.*.commission_value' => 'nullable|numeric|min:0',
        ]);

        $staffTarget->update(array_filter([
            'title'        => $data['title']       ?? null,
            'description'  => $data['description'] ?? null,
            'period_start' => $data['period_start']?? null,
            'period_end'   => $data['period_end']  ?? null,
        ], fn ($v) => $v !== null));

        if (!empty($data['criteria'])) {
            $staffTarget->criteria()->delete();
            foreach ($data['criteria'] as $c) {
                StaffTargetCriterion::create([
                    'target_id'        => $staffTarget->id,
                    'type'             => $c['type'],
                    'label'            => $c['label'],
                    'unit'             => $c['unit'] ?? $this->defaultUnit($c['type']),
                    'goal_value'       => $c['goal_value'],
                    'commission_type'  => $c['commission_type'],
                    'commission_value' => $c['commission_value'] ?? null,
                ]);
            }
        }

        return response()->json(['data' => $this->format($staffTarget->load(['user', 'assignedBy', 'criteria']))]);
    }

    // ── Delete ────────────────────────────────────────────────────────────────

    public function destroy(StaffTarget $staffTarget)
    {
        $this->authorizePermission('staff_targets.manage');

        if ($staffTarget->status === 'verified') {
            abort(422, 'Verified targets cannot be deleted.');
        }

        $staffTarget->delete();
        return response()->json(null, 204);
    }

    // ── Self-report: staff enters achieved values ─────────────────────────────

    public function selfReport(Request $request, StaffTarget $staffTarget)
    {
        $this->authorizePermission('staff_targets.submit');

        $user = auth()->user();
        if ($staffTarget->user_id !== $user->id && !$user->hasPermission('staff_targets.manage')) {
            abort(403, 'You can only self-report on your own targets.');
        }

        if (!in_array($staffTarget->status, ['active', 'self_reported'])) {
            abort(422, 'This target cannot be updated in its current status.');
        }

        $data = $request->validate([
            'criteria'             => 'required|array',
            'criteria.*.id'        => 'required|uuid',
            'criteria.*.achieved_value' => 'required|numeric|min:0',
            'notes'                => 'nullable|string|max:2000',
        ]);

        foreach ($data['criteria'] as $entry) {
            StaffTargetCriterion::where('target_id', $staffTarget->id)
                ->where('id', $entry['id'])
                ->update(['achieved_value' => $entry['achieved_value']]);
        }

        $staffTarget->update(['status' => 'self_reported']);
        $staffTarget->load(['user', 'assignedBy', 'criteria']);

        // Notify supervisor that self-report needs verification
        $supervisor = $staffTarget->user->supervisor;
        if ($supervisor) {
            $supervisor->notify(new StaffTargetSelfReportedNotification($staffTarget->user->tenant, $staffTarget));
        }

        return response()->json(['data' => $this->format($staffTarget)]);
    }

    // ── Verify: supervisor confirms values and calculates commission ───────────

    public function verify(Request $request, StaffTarget $staffTarget)
    {
        $this->authorizePermission('staff_targets.verify');

        if ($staffTarget->status === 'verified') {
            abort(422, 'This target is already verified.');
        }

        $data = $request->validate([
            'criteria'                   => 'required|array',
            'criteria.*.id'              => 'required|uuid',
            'criteria.*.verified_value'  => 'required|numeric|min:0',
            'supervisor_notes'           => 'nullable|string|max:2000',
        ]);

        foreach ($data['criteria'] as $entry) {
            $criterion = StaffTargetCriterion::where('target_id', $staffTarget->id)
                ->where('id', $entry['id'])
                ->firstOrFail();

            $verified  = (float) $entry['verified_value'];
            $goalMet   = $verified >= $criterion->goal_value;
            $criterion->update([
                'verified_value'   => $verified,
                'goal_met'         => $goalMet,
                'commission_earned'=> $criterion->fill(['verified_value' => $verified, 'goal_met' => $goalMet])
                                                ->calculateCommission(),
            ]);
        }

        $staffTarget->update([
            'status'           => 'verified',
            'supervisor_notes' => $data['supervisor_notes'] ?? null,
            'verified_by'      => auth()->id(),
            'verified_at'      => now(),
        ]);

        $staffTarget->load(['user', 'assignedBy', 'verifiedBy', 'criteria']);

        // Notify staff member of verification result with commission details
        $staffTarget->user->notify(
            new StaffTargetVerifiedNotification($staffTarget->user->tenant, $staffTarget)
        );

        return response()->json(['data' => $this->format($staffTarget)]);
    }

    // ── Commission summary ────────────────────────────────────────────────────

    public function summary(Request $request)
    {
        $this->authorizePermission('staff_targets.submit');
        $user = auth()->user();

        $query = StaffTarget::with('criteria')->where('status', 'verified');

        if ($user->hasPermission('staff_targets.manage') || $user->hasPermission('staff_targets.verify')) {
            if (!$user->hasPermission('staff_reports.view_all')) {
                $subordinateIds = User::where('tenant_id', $user->tenant_id)
                    ->where('supervisor_id', $user->id)
                    ->pluck('id')
                    ->push($user->id);
                $query->whereIn('user_id', $subordinateIds);
            }
        } else {
            $query->where('user_id', $user->id);
        }

        if ($request->user_id) $query->where('user_id', $request->user_id);

        $targets = $query->get();

        // Group commission totals per user
        $grouped = $targets->groupBy('user_id')->map(function ($userTargets) {
            $u = User::find($userTargets->first()->user_id);
            return [
                'user'              => ['id' => $u->id, 'name' => $u->name],
                'total_commission'  => $userTargets->sum(fn ($t) => $t->totalCommissionEarned()),
                'targets_count'     => $userTargets->count(),
                'targets'           => $userTargets->map(fn ($t) => [
                    'id'               => $t->id,
                    'title'            => $t->title,
                    'period'           => $t->period_start->format('d M') . ' – ' . $t->period_end->format('d M Y'),
                    'commission_earned'=> $t->totalCommissionEarned(),
                ]),
            ];
        })->values();

        return response()->json(['data' => $grouped]);
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private function defaultUnit(string $type): string
    {
        return match ($type) {
            'customer_count' => 'customers',
            'revenue'        => 'KES',
            'item_sales'     => 'units',
            default          => 'units',
        };
    }

    private function format(StaffTarget $t): array
    {
        return [
            'id'               => $t->id,
            'user'             => ['id' => $t->user->id, 'name' => $t->user->name],
            'assigned_by'      => ['id' => $t->assignedBy->id, 'name' => $t->assignedBy->name],
            'title'            => $t->title,
            'description'      => $t->description,
            'period_start'     => $t->period_start->toDateString(),
            'period_end'       => $t->period_end->toDateString(),
            'status'           => $t->status,
            'supervisor_notes' => $t->supervisor_notes,
            'verified_by'      => $t->verifiedBy ? ['id' => $t->verifiedBy->id, 'name' => $t->verifiedBy->name] : null,
            'verified_at'      => $t->verified_at?->toISOString(),
            'total_commission' => $t->totalCommissionEarned(),
            'criteria'         => $t->criteria->map(fn ($c) => [
                'id'               => $c->id,
                'type'             => $c->type,
                'label'            => $c->label,
                'unit'             => $c->unit,
                'goal_value'       => $c->goal_value,
                'achieved_value'   => $c->achieved_value,
                'verified_value'   => $c->verified_value,
                'goal_met'         => $c->goal_met,
                'commission_type'  => $c->commission_type,
                'commission_value' => $c->commission_value,
                'commission_earned'=> $c->commission_earned,
            ])->values()->all(),
            'created_at' => $t->created_at->toISOString(),
        ];
    }
}
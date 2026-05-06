<?php

namespace App\Http\Controllers;

use App\Models\StaffTarget;
use App\Models\StaffTargetCriterion;
use App\Models\User;
use App\Notifications\StaffTargetAssignedNotification;
use App\Notifications\StaffTargetAssignedSupervisorNotification;
use App\Notifications\StaffTargetManagerAssignedNotification;
use App\Notifications\StaffTargetManagerVerifiedNotification;
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

        $query = StaffTarget::with(['user', 'assignedBy', 'verifiedBy', 'manager', 'criteria'])
            ->orderBy('period_start', 'desc')
            ->orderBy('created_at', 'desc');

        if ($user->hasPermission('staff_targets.manage') || $user->hasPermission('staff_targets.verify')) {
            if (!$user->hasPermission('staff_reports.view_all')) {
                $subordinateIds = User::where('tenant_id', $user->tenant_id)
                    ->where('supervisor_id', $user->id)
                    ->pluck('id')
                    ->push($user->id)
                    ->all();
                $query->where(function ($q) use ($subordinateIds, $user) {
                    $q->whereIn('user_id', $subordinateIds)
                      ->orWhere('manager_id', $user->id);
                });
            }
        } else {
            $query->where(function ($q) use ($user) {
                $q->where('user_id', $user->id)
                  ->orWhere('manager_id', $user->id);
            });
        }

        if ($request->user_id) $query->where('user_id', $request->user_id);
        if ($request->status)  $query->where('status', $request->status);
        if ($request->boolean('managed_only')) {
            $query->where('manager_id', $user->id);
        }

        return response()->json(['data' => $query->get()->map(fn ($t) => $this->format($t))]);
    }

    // ── Create ────────────────────────────────────────────────────────────────

    public function store(Request $request)
    {
        $this->authorizePermission('staff_targets.manage');
        $user = auth()->user();

        $data = $request->validate([
            'user_id'                => 'required|uuid',
            'title'                  => 'required|string|max:255',
            'description'            => 'nullable|string|max:2000',
            'period_start'           => 'required|date',
            'period_end'             => 'required|date|after_or_equal:period_start',
            'group_commission_type'  => 'nullable|in:none,fixed,percentage',
            'group_commission_value' => 'nullable|numeric|min:0',
            'staff_salary'           => 'nullable|numeric|min:0',
            'deduct_on_failure'      => 'nullable|boolean',
            'manager_id'             => 'nullable|uuid|different:user_id',
            'manager_commission_type'  => 'nullable|in:none,fixed,percentage',
            'manager_commission_value' => 'nullable|numeric|min:0',
            'criteria'               => 'required|array|min:1',
            'criteria.*.type'        => 'required|in:customer_count,revenue,item_sales,custom',
            'criteria.*.label'       => 'required|string|max:255',
            'criteria.*.unit'        => 'nullable|string|max:50',
            'criteria.*.goal_value'        => 'required|numeric|min:0',
            'criteria.*.commission_type'   => 'required|in:none,fixed,percentage',
            'criteria.*.commission_value'  => 'nullable|numeric|min:0',
        ]);

        $targetUser = User::where('tenant_id', $user->tenant_id)->findOrFail($data['user_id']);

        $manager = null;
        if (!empty($data['manager_id'])) {
            $manager = User::where('tenant_id', $user->tenant_id)->findOrFail($data['manager_id']);
        }

        $target = StaffTarget::create([
            'user_id'               => $targetUser->id,
            'assigned_by'           => $user->id,
            'title'                 => $data['title'],
            'description'           => $data['description'] ?? null,
            'period_start'          => $data['period_start'],
            'period_end'            => $data['period_end'],
            'group_commission_type' => $data['group_commission_type'] ?? 'none',
            'group_commission_value'=> $data['group_commission_value'] ?? null,
            'staff_salary'          => $data['staff_salary'] ?? null,
            'deduct_on_failure'     => $data['deduct_on_failure'] ?? false,
            'manager_id'                => $manager?->id,
            'manager_commission_type'   => $manager ? ($data['manager_commission_type'] ?? 'none') : 'none',
            'manager_commission_value'  => $manager ? ($data['manager_commission_value'] ?? null) : null,
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

        $target->load(['user.supervisor', 'assignedBy', 'manager', 'criteria']);

        $targetUser->notify(new StaffTargetAssignedNotification($targetUser->tenant, $target));

        $supervisor = $targetUser->supervisor;
        if ($supervisor && $supervisor->id !== $targetUser->id) {
            $supervisor->notify(new StaffTargetAssignedSupervisorNotification($targetUser->tenant, $target));
        }

        if ($manager && $manager->id !== $targetUser->id) {
            $manager->notify(new StaffTargetManagerAssignedNotification($targetUser->tenant, $target));
        }

        return response()->json(['data' => $this->format($target)], 201);
    }

    // ── Update ────────────────────────────────────────────────────────────────

    public function update(Request $request, StaffTarget $staffTarget)
    {
        $this->authorizePermission('staff_targets.manage');

        if (!in_array($staffTarget->status, ['active'])) {
            abort(422, 'Only active targets can be edited.');
        }

        $data = $request->validate([
            'title'                  => 'sometimes|string|max:255',
            'description'            => 'nullable|string|max:2000',
            'period_start'           => 'sometimes|date',
            'period_end'             => 'sometimes|date',
            'group_commission_type'  => 'nullable|in:none,fixed,percentage',
            'group_commission_value' => 'nullable|numeric|min:0',
            'staff_salary'           => 'nullable|numeric|min:0',
            'deduct_on_failure'      => 'nullable|boolean',
            'manager_id'                 => 'nullable|uuid',
            'manager_commission_type'    => 'nullable|in:none,fixed,percentage',
            'manager_commission_value'   => 'nullable|numeric|min:0',
            'criteria'               => 'sometimes|array|min:1',
            'criteria.*.type'        => 'required_with:criteria|in:customer_count,revenue,item_sales,custom',
            'criteria.*.label'       => 'required_with:criteria|string|max:255',
            'criteria.*.unit'        => 'nullable|string|max:50',
            'criteria.*.goal_value'        => 'required_with:criteria|numeric|min:0',
            'criteria.*.commission_type'   => 'required_with:criteria|in:none,fixed,percentage',
            'criteria.*.commission_value'  => 'nullable|numeric|min:0',
        ]);

        $previousManagerId = $staffTarget->manager_id;

        $patch = array_filter([
            'title'                 => $data['title']        ?? null,
            'description'           => $data['description']  ?? null,
            'period_start'          => $data['period_start'] ?? null,
            'period_end'            => $data['period_end']   ?? null,
            'group_commission_type' => $data['group_commission_type']  ?? null,
            'group_commission_value'=> $data['group_commission_value'] ?? null,
            'staff_salary'          => $data['staff_salary']           ?? null,
            'deduct_on_failure'     => $data['deduct_on_failure']      ?? null,
        ], fn ($v) => $v !== null);

        if (isset($data['deduct_on_failure'])) {
            $patch['deduct_on_failure'] = $data['deduct_on_failure'];
        }

        if (array_key_exists('manager_id', $data)) {
            if (!empty($data['manager_id']) && $data['manager_id'] === $staffTarget->user_id) {
                abort(422, 'A staff member cannot manage their own target.');
            }
            $patch['manager_id']               = $data['manager_id'] ?: null;
            $patch['manager_commission_type']  = $data['manager_id']
                ? ($data['manager_commission_type'] ?? 'none')
                : 'none';
            $patch['manager_commission_value'] = $data['manager_id']
                ? ($data['manager_commission_value'] ?? null)
                : null;
        } else {
            if (array_key_exists('manager_commission_type', $data)) {
                $patch['manager_commission_type'] = $data['manager_commission_type'];
            }
            if (array_key_exists('manager_commission_value', $data)) {
                $patch['manager_commission_value'] = $data['manager_commission_value'];
            }
        }

        $staffTarget->update($patch);

        if (!empty($patch['manager_id']) && $patch['manager_id'] !== $previousManagerId) {
            $staffTarget->load(['user', 'assignedBy', 'manager']);
            $staffTarget->manager?->notify(
                new StaffTargetManagerAssignedNotification($staffTarget->user->tenant, $staffTarget)
            );
        }

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

        return response()->json(['data' => $this->format($staffTarget->load(['user', 'assignedBy', 'manager', 'criteria']))]);
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

    // ── Self-report ───────────────────────────────────────────────────────────

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
            'criteria'                   => 'required|array',
            'criteria.*.id'              => 'required|uuid',
            'criteria.*.achieved_value'  => 'required|numeric|min:0',
        ]);

        foreach ($data['criteria'] as $entry) {
            StaffTargetCriterion::where('target_id', $staffTarget->id)
                ->where('id', $entry['id'])
                ->update(['achieved_value' => $entry['achieved_value']]);
        }

        $staffTarget->update(['status' => 'self_reported']);
        $staffTarget->load(['user', 'assignedBy', 'criteria']);

        $supervisor = $staffTarget->user->supervisor;
        if ($supervisor) {
            $supervisor->notify(new StaffTargetSelfReportedNotification($staffTarget->user->tenant, $staffTarget));
        }

        return response()->json(['data' => $this->format($staffTarget)]);
    }

    // ── Verify ────────────────────────────────────────────────────────────────

    public function verify(Request $request, StaffTarget $staffTarget)
    {
        $this->authorizePermission('staff_targets.verify');

        if ($staffTarget->status === 'verified') {
            abort(422, 'This target is already verified.');
        }

        $data = $request->validate([
            'criteria'                  => 'required|array',
            'criteria.*.id'             => 'required|uuid',
            'criteria.*.verified_value' => 'required|numeric|min:0',
            'supervisor_notes'          => 'nullable|string|max:2000',
        ]);

        foreach ($data['criteria'] as $entry) {
            $criterion = StaffTargetCriterion::where('target_id', $staffTarget->id)
                ->where('id', $entry['id'])
                ->firstOrFail();

            $verified = (float) $entry['verified_value'];
            $goalMet  = $verified >= $criterion->goal_value;
            $criterion->update([
                'verified_value'    => $verified,
                'goal_met'          => $goalMet,
                'commission_earned' => $criterion->fill(['verified_value' => $verified, 'goal_met' => $goalMet])
                                                  ->calculateCommission(),
            ]);
        }

        // Reload criteria to check all-goals-met after updates
        $staffTarget->load('criteria');
        $allGoalsMet = $staffTarget->criteria->every(fn ($c) => $c->goal_met === true);

        // Group bonus (fires only when ALL goals met)
        $groupCommissionEarned = 0.0;
        if ($staffTarget->group_commission_type !== 'none' && $allGoalsMet) {
            $groupCommissionEarned = $staffTarget->group_commission_type === 'fixed'
                ? (float) ($staffTarget->group_commission_value ?? 0)
                : round((float) ($staffTarget->group_commission_value ?? 0) / 100 * (float) ($staffTarget->staff_salary ?? 0), 2);
        }

        // Salary deduction (fires when any goal is missed)
        $salaryDeductionEarned = 0.0;
        if (!$allGoalsMet && $staffTarget->deduct_on_failure && $staffTarget->staff_salary) {
            $salaryDeductionEarned = round((float) $staffTarget->staff_salary / 2, 2);
        }

        $staffTarget->update([
            'status'                  => 'verified',
            'supervisor_notes'        => $data['supervisor_notes'] ?? null,
            'verified_by'             => auth()->id(),
            'verified_at'             => now(),
            'group_commission_earned' => $groupCommissionEarned,
            'salary_deduction_earned' => $salaryDeductionEarned,
        ]);

        $managerCommissionEarned = $staffTarget->fresh()->load('criteria')->calculateManagerCommission($allGoalsMet);
        $staffTarget->update(['manager_commission_earned' => $managerCommissionEarned]);

        $staffTarget->load(['user', 'assignedBy', 'verifiedBy', 'manager', 'criteria']);

        $staffTarget->user->notify(
            new StaffTargetVerifiedNotification($staffTarget->user->tenant, $staffTarget)
        );

        if ($staffTarget->manager && $staffTarget->manager->id !== $staffTarget->user_id) {
            $staffTarget->manager->notify(
                new StaffTargetManagerVerifiedNotification($staffTarget->user->tenant, $staffTarget)
            );
        }

        return response()->json(['data' => $this->format($staffTarget)]);
    }

    // ── Commission summary ────────────────────────────────────────────────────

    public function summary(Request $request)
    {
        $this->authorizePermission('staff_targets.submit');
        $user = auth()->user();

        $relevantUserIds = null;
        if ($user->hasPermission('staff_targets.manage') || $user->hasPermission('staff_targets.verify')) {
            if (!$user->hasPermission('staff_reports.view_all')) {
                $relevantUserIds = User::where('tenant_id', $user->tenant_id)
                    ->where('supervisor_id', $user->id)
                    ->pluck('id')
                    ->push($user->id)
                    ->all();
            }
        } else {
            $relevantUserIds = [$user->id];
        }

        $query = StaffTarget::with(['criteria', 'user', 'manager'])->where('status', 'verified');
        if ($relevantUserIds !== null) {
            $query->where(function ($q) use ($relevantUserIds) {
                $q->whereIn('user_id', $relevantUserIds)
                  ->orWhereIn('manager_id', $relevantUserIds);
            });
        }
        if ($request->user_id) {
            $query->where(function ($q) use ($request) {
                $q->where('user_id', $request->user_id)
                  ->orWhere('manager_id', $request->user_id);
            });
        }

        $targets = $query->get();
        $entries = [];

        foreach ($targets as $t) {
            $period = $t->period_start->format('d M') . ' – ' . $t->period_end->format('d M Y');

            // Staff (assignee) bucket
            if ($relevantUserIds === null || in_array($t->user_id, $relevantUserIds, true) || ($request->user_id && $t->user_id === $request->user_id)) {
                $uid = $t->user_id;
                $entries[$uid] ??= $this->emptyEntry($t->user);
                $entries[$uid]['gross_commission']  += $t->grossCommission();
                $entries[$uid]['salary_deductions'] += (float) ($t->salary_deduction_earned ?? 0);
                $entries[$uid]['total_commission']  += $t->totalCommissionEarned();
                $entries[$uid]['targets_count']++;
                $entries[$uid]['targets'][] = [
                    'id'                => $t->id,
                    'title'              => $t->title,
                    'period'             => $period,
                    'commission_earned'  => $t->totalCommissionEarned(),
                    'salary_deduction'   => (float) ($t->salary_deduction_earned ?? 0),
                ];
            }

            // Manager (override commission) bucket
            if ($t->manager_id && (
                $relevantUserIds === null
                || in_array($t->manager_id, $relevantUserIds, true)
                || ($request->user_id && $t->manager_id === $request->user_id)
            )) {
                $mid = $t->manager_id;
                $entries[$mid] ??= $this->emptyEntry($t->manager);
                $entries[$mid]['manager_commission'] += (float) ($t->manager_commission_earned ?? 0);
                $entries[$mid]['managed_targets'][] = [
                    'id'                => $t->id,
                    'title'             => $t->title,
                    'period'            => $period,
                    'staff'             => ['id' => $t->user->id, 'name' => $t->user->name],
                    'commission_earned' => (float) ($t->manager_commission_earned ?? 0),
                ];
            }
        }

        // Roll manager commission into the user's total
        foreach ($entries as &$e) {
            $e['total_commission'] = round($e['total_commission'] + $e['manager_commission'], 2);
        }

        return response()->json(['data' => array_values($entries)]);
    }

    private function emptyEntry($u): array
    {
        return [
            'user'               => ['id' => $u->id, 'name' => $u->name],
            'gross_commission'   => 0.0,
            'salary_deductions'  => 0.0,
            'total_commission'   => 0.0,
            'manager_commission' => 0.0,
            'targets_count'      => 0,
            'targets'            => [],
            'managed_targets'    => [],
        ];
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private function defaultUnit(string $type): string
    {
        return match ($type) {
            'customer_count' => 'customers',
            'revenue'        => 'units',
            'item_sales'     => 'units',
            default          => 'units',
        };
    }

    private function format(StaffTarget $t): array
    {
        $allGoalsMet = $t->status === 'verified'
            ? $t->criteria->every(fn ($c) => $c->goal_met === true)
            : null;

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
            // Commission fields
            'group_commission_type'   => $t->group_commission_type,
            'group_commission_value'  => $t->group_commission_value,
            'group_commission_earned' => $t->group_commission_earned,
            'staff_salary'            => $t->staff_salary,
            'deduct_on_failure'       => (bool) $t->deduct_on_failure,
            'salary_deduction_earned' => $t->salary_deduction_earned,
            // Manager (team-lead) fields
            'manager'                  => $t->manager ? ['id' => $t->manager->id, 'name' => $t->manager->name] : null,
            'manager_commission_type'  => $t->manager_commission_type,
            'manager_commission_value' => $t->manager_commission_value,
            'manager_commission_earned'=> $t->manager_commission_earned,
            'all_goals_met'           => $allGoalsMet,
            'gross_commission'        => $t->grossCommission(),
            'total_commission'        => $t->totalCommissionEarned(),
            'criteria'                => $t->criteria->map(fn ($c) => [
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

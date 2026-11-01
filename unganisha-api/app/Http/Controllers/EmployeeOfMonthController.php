<?php

namespace App\Http\Controllers;

use App\Models\EmployeeOfMonthCycle;
use App\Models\EmployeeOfMonthVote;
use App\Models\User;
use App\Services\EmployeeOfMonthService;
use App\Traits\AuthorizesPermissions;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class EmployeeOfMonthController extends Controller
{
    use AuthorizesPermissions;

    /**
     * The voting widget's one call: the open cycle (if any — otherwise the
     * most recently closed one, so there's always something to show), the
     * candidate list (every active employee except the caller), whether the
     * caller already voted, and turnout (how many have voted so far, out of
     * how many are eligible). The per-candidate breakdown (`results`) is
     * withheld while the cycle is still `open` — showing it live would let
     * people see who's ahead and vote tactically — and only released once
     * the cycle is automatically tallied/closed.
     */
    public function current(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;
        $userId = auth()->id();

        $cycle = EmployeeOfMonthCycle::where('tenant_id', $tenantId)->where('status', 'open')
            ->orderByDesc('voting_opens_on')->first()
            ?? EmployeeOfMonthCycle::where('tenant_id', $tenantId)->where('status', 'closed')
                ->orderByDesc('voting_closes_on')->first();

        if (!$cycle) {
            return response()->json(['data' => null]);
        }

        $myVote = EmployeeOfMonthVote::where('cycle_id', $cycle->id)->where('voter_id', $userId)->first();

        $candidates = User::where('tenant_id', $tenantId)->where('is_active', true)
            ->where('id', '!=', $userId)->orderBy('name')->get(['id', 'name']);

        return response()->json(['data' => [
            'cycle' => $this->cyclePayload($cycle),
            'is_open_now' => $cycle->isOpenNow(),
            'has_voted' => (bool) $myVote,
            'my_vote' => $myVote ? ['candidate_id' => $myVote->candidate_id, 'reason' => $myVote->reason] : null,
            'candidates' => $candidates,
            'turnout' => $this->turnoutFor($cycle, $tenantId),
            'results' => $cycle->status === 'closed' ? $this->resultsFor($cycle, $tenantId) : null,
        ]]);
    }

    public function vote(Request $request)
    {
        $tenantId = auth()->user()->tenant_id;
        $userId = auth()->id();

        $data = $request->validate([
            'cycle_id' => ['required', 'uuid', Rule::exists('employee_of_month_cycles', 'id')->where('tenant_id', $tenantId)],
            'candidate_id' => ['required', 'uuid', Rule::exists('users', 'id')->where('tenant_id', $tenantId)->where('is_active', true)],
            'reason' => 'required|string|min:3|max:1000',
        ]);

        if ($data['candidate_id'] === $userId) {
            throw ValidationException::withMessages(['candidate_id' => 'Haiwezekani kujipigia kura wewe mwenyewe.']);
        }

        $cycle = EmployeeOfMonthCycle::where('tenant_id', $tenantId)->findOrFail($data['cycle_id']);
        if (!$cycle->isOpenNow()) {
            return response()->json(['message' => 'Muda wa kupiga kura haujafunguliwa au umefungwa.'], 422);
        }

        if (EmployeeOfMonthVote::where('cycle_id', $cycle->id)->where('voter_id', $userId)->exists()) {
            return response()->json(['message' => 'Umepiga kura kwenye mzunguko huu tayari.'], 422);
        }

        $vote = EmployeeOfMonthVote::create([
            'tenant_id' => $tenantId,
            'cycle_id' => $cycle->id,
            'voter_id' => $userId,
            'candidate_id' => $data['candidate_id'],
            'reason' => $data['reason'],
        ]);

        return response()->json(['data' => $vote], 201);
    }

    /** History of all cycles — admin/payroll staff only. */
    public function index()
    {
        $this->authorizePermission('payroll.manage', 'payroll.view');
        $tenantId = auth()->user()->tenant_id;

        $cycles = EmployeeOfMonthCycle::where('tenant_id', $tenantId)
            ->with('winner:id,name')
            ->orderByDesc('period_month_key')->get();

        return response()->json(['data' => $cycles->map(fn ($c) => $this->cyclePayload($c))]);
    }

    /** Full vote breakdown including each voter's reason — admin/payroll staff only. */
    public function votes(EmployeeOfMonthCycle $cycle)
    {
        $this->authorizePermission('payroll.manage', 'payroll.view');
        if ($cycle->tenant_id !== auth()->user()->tenant_id) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $votes = EmployeeOfMonthVote::where('cycle_id', $cycle->id)
            ->with(['voter:id,name', 'candidate:id,name'])
            ->orderBy('created_at')->get();

        return response()->json(['data' => [
            'cycle' => $this->cyclePayload($cycle),
            'votes' => $votes,
            'results' => $this->resultsFor($cycle, $cycle->tenant_id),
        ]]);
    }

    /** Set or update the prize for a cycle — creates/updates the winner's Commission if already tallied. */
    public function setPrize(Request $request, EmployeeOfMonthCycle $cycle, EmployeeOfMonthService $service)
    {
        $this->authorizePermission('payroll.manage');
        if ($cycle->tenant_id !== auth()->user()->tenant_id) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $data = $request->validate(['prize_amount' => 'required|numeric|min:0.01']);

        $cycle->update(['prize_amount' => $data['prize_amount']]);
        $service->maybeCreateOrUpdateCommission($cycle->fresh());

        return response()->json(['data' => $this->cyclePayload($cycle->fresh()->load('winner:id,name'))]);
    }

    private function cyclePayload(EmployeeOfMonthCycle $cycle): array
    {
        return [
            'id' => $cycle->id,
            'period_month_key' => $cycle->period_month_key,
            'voting_opens_on' => $cycle->voting_opens_on->toDateString(),
            'voting_closes_on' => $cycle->voting_closes_on->toDateString(),
            'prize_amount' => $cycle->prize_amount,
            'status' => $cycle->status,
            'winner' => $cycle->winner ? ['id' => $cycle->winner->id, 'name' => $cycle->winner->name] : null,
            'winner_vote_count' => $cycle->winner_vote_count,
            'winner_commission_id' => $cycle->winner_commission_id,
            'tallied_at' => $cycle->tallied_at?->toIso8601String(),
        ];
    }

    /** How many eligible (active) staff have voted so far, out of how many are eligible. */
    private function turnoutFor(EmployeeOfMonthCycle $cycle, string $tenantId): array
    {
        $total = User::where('tenant_id', $tenantId)->where('is_active', true)->count();
        $voted = EmployeeOfMonthVote::where('cycle_id', $cycle->id)->count();

        return ['voted' => $voted, 'total' => $total, 'remaining' => max(0, $total - $voted)];
    }

    /** Every active employee, 0 votes included — "list ya wafanyakazi wote na kura zao", not just those who got any. */
    private function resultsFor(EmployeeOfMonthCycle $cycle, string $tenantId): array
    {
        $counts = EmployeeOfMonthVote::where('cycle_id', $cycle->id)
            ->selectRaw('candidate_id, count(*) as votes')->groupBy('candidate_id')
            ->pluck('votes', 'candidate_id');

        return User::where('tenant_id', $tenantId)->where('is_active', true)->orderBy('name')
            ->get(['id', 'name'])
            ->map(fn ($u) => ['user_id' => $u->id, 'name' => $u->name, 'votes' => (int) ($counts[$u->id] ?? 0)])
            ->sortByDesc('votes')->values()->all();
    }
}

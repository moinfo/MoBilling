<?php

namespace App\Services;

use App\Models\Commission;
use App\Models\EmployeeOfMonthCycle;
use App\Models\EmployeeOfMonthVote;
use App\Models\PayrollRun;
use Illuminate\Support\Facades\DB;

/**
 * Shared between the closing cron command and the admin "set prize"
 * endpoint, so a cycle tallied with no prize yet (or a prize changed after
 * closing) both end up at the same place: exactly one pending Commission
 * for the winner, kept in sync with prize_amount.
 */
class EmployeeOfMonthService
{
    /** Counts votes, picks a winner (most votes; ties broken by name), and closes the cycle. Idempotent. */
    public function tally(EmployeeOfMonthCycle $cycle): void
    {
        if ($cycle->status === 'closed') {
            return;
        }

        $tally = EmployeeOfMonthVote::where('cycle_id', $cycle->id)
            ->selectRaw('candidate_id, count(*) as votes')
            ->groupBy('candidate_id')
            ->orderByDesc('votes')
            ->with('candidate:id,name')
            ->get();

        $top = $tally->first();

        // Tie-break deterministically: among the top vote count, the
        // alphabetically-first name — never arbitrary row order.
        $winners = $top ? $tally->where('votes', $top->votes)->sortBy(fn ($t) => $t->candidate?->name)->values() : collect();
        $winner = $winners->first();

        $cycle->update([
            'status' => 'closed',
            'tallied_at' => now(),
            'winner_user_id' => $winner?->candidate_id,
            'winner_vote_count' => $winner?->votes,
        ]);

        $this->maybeCreateOrUpdateCommission($cycle->fresh());
    }

    /**
     * Creates the winner's prize Commission once both a winner and a
     * prize_amount exist, or updates the amount on an already-created
     * pending one if the admin changes prize_amount afterward. Never
     * double-creates (guarded by winner_commission_id).
     */
    public function maybeCreateOrUpdateCommission(EmployeeOfMonthCycle $cycle): void
    {
        if (!$cycle->winner_user_id || !$cycle->prize_amount) {
            return;
        }

        if ($cycle->winner_commission_id) {
            $commission = Commission::find($cycle->winner_commission_id);
            if ($commission && $commission->status === 'pending' && (float) $commission->amount !== (float) $cycle->prize_amount) {
                $commission->update(['amount' => $cycle->prize_amount]);
            }
            return;
        }

        DB::transaction(function () use ($cycle) {
            // Pay out through the earliest month whose payroll isn't finalized
            // yet, so a late prize-amount entry never fails outright — it just
            // lands in the next open payroll instead of the one that already closed.
            $payoutMonthKey = now()->format('Y-m');
            while (PayrollRun::where('tenant_id', $cycle->tenant_id)->where('month_key', $payoutMonthKey)->where('status', 'finalized')->exists()) {
                $payoutMonthKey = \Carbon\Carbon::createFromFormat('Y-m', $payoutMonthKey)->addMonth()->format('Y-m');
            }

            $commission = Commission::create([
                'tenant_id' => $cycle->tenant_id,
                'user_id' => $cycle->winner_user_id,
                'amount' => $cycle->prize_amount,
                'earned_date' => now(),
                'payout_month_key' => $payoutMonthKey,
                'status' => 'pending',
                'notes' => "Employee of the Month — {$cycle->period_month_key}",
            ]);

            $cycle->update(['winner_commission_id' => $commission->id]);
        });
    }
}

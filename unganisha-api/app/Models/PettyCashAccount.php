<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class PettyCashAccount extends Model
{
    use HasFactory, HasUuids, SoftDeletes, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'name', 'opening_balance', 'is_active',
    ];

    protected $casts = [
        'opening_balance' => 'decimal:2',
        'is_active' => 'boolean',
    ];

    public function transactions()
    {
        return $this->hasMany(PettyCashTransaction::class);
    }

    public function reconciliations()
    {
        return $this->hasMany(PettyCashReconciliation::class);
    }

    public function expenses()
    {
        return $this->hasMany(Expense::class);
    }

    /**
     * Compute the petty-cash balance figures for this account.
     *
     * - verified  = the official remaining float (what the user sees as
     *               "balance"). Subtracts only APPROVED expenses.
     * - committed = the physically-remaining cash. Also subtracts expenses
     *               still awaiting approval, since that cash has already left
     *               the till.
     * - pending_total / pending_count describe the gap — expenses awaiting
     *   administrator approval.
     * - Rejected expenses never count (the cash is expected back).
     *
     * verified - pending_total = committed.
     *
     * The insufficient-funds guard on new expenses uses `committed` so
     * users can't keep spending physical cash that's already been taken.
     */
    public function balances(): array
    {
        $tx = $this->transactions()
            ->selectRaw("
                COALESCE(SUM(CASE WHEN type IN ('top_up','adjustment_in') THEN amount ELSE 0 END), 0) AS additions,
                COALESCE(SUM(CASE WHEN type IN ('return','adjustment_out') THEN amount ELSE 0 END), 0) AS subtractions
            ")
            ->first();

        $exp = Expense::where('petty_cash_account_id', $this->id)
            ->where('approval_status', '!=', 'rejected')
            ->selectRaw("
                COALESCE(SUM(CASE WHEN approval_status = 'approved' THEN amount ELSE 0 END), 0) AS approved_total,
                COALESCE(SUM(CASE WHEN approval_status = 'pending' THEN amount ELSE 0 END), 0) AS pending_total,
                SUM(CASE WHEN approval_status = 'pending' THEN 1 ELSE 0 END) AS pending_count
            ")
            ->first();

        $opening = (float) $this->opening_balance;
        $verified = round($opening + (float) $tx->additions - (float) $tx->subtractions - (float) $exp->approved_total, 2);
        $pendingTotal = round((float) $exp->pending_total, 2);
        $committed = round($verified - $pendingTotal, 2);

        return [
            'verified' => $verified,
            'committed' => $committed,
            'pending_total' => $pendingTotal,
            'pending_count' => (int) $exp->pending_count,
        ];
    }
}

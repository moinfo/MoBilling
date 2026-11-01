<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class EmployeeOfMonthCycle extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'period_month_key', 'voting_opens_on', 'voting_closes_on',
        'prize_amount', 'status', 'winner_user_id', 'winner_vote_count',
        'winner_commission_id', 'tallied_at',
    ];

    protected $casts = [
        'voting_opens_on' => 'date',
        'voting_closes_on' => 'date',
        'tallied_at' => 'datetime',
    ];

    public function votes(): HasMany
    {
        return $this->hasMany(EmployeeOfMonthVote::class, 'cycle_id');
    }

    public function winner(): BelongsTo
    {
        return $this->belongsTo(User::class, 'winner_user_id');
    }

    public function winnerCommission(): BelongsTo
    {
        return $this->belongsTo(Commission::class, 'winner_commission_id');
    }

    public function isOpenNow(): bool
    {
        $today = now()->toDateString();

        return $this->status === 'open'
            && $today >= $this->voting_opens_on->toDateString()
            && $today <= $this->voting_closes_on->toDateString();
    }
}

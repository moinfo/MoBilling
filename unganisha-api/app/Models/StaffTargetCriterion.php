<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class StaffTargetCriterion extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'target_id', 'type', 'label', 'unit', 'goal_value',
        'achieved_value', 'verified_value', 'goal_met',
        'commission_type', 'commission_value', 'commission_earned',
    ];

    protected $casts = [
        'goal_value'       => 'float',
        'achieved_value'   => 'float',
        'verified_value'   => 'float',
        'commission_value' => 'float',
        'commission_earned'=> 'float',
        'goal_met'         => 'boolean',
    ];

    public function target(): BelongsTo
    {
        return $this->belongsTo(StaffTarget::class);
    }

    public function calculateCommission(): float
    {
        if ($this->commission_type === 'none' || !$this->goal_met) {
            return 0;
        }
        if ($this->commission_type === 'fixed') {
            return (float) $this->commission_value;
        }
        // percentage of verified_value
        return round((float) $this->commission_value / 100 * (float) $this->verified_value, 2);
    }
}

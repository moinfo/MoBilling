<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class StaffTarget extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'user_id', 'assigned_by', 'title', 'description',
        'period_start', 'period_end', 'status',
        'supervisor_notes', 'verified_by', 'verified_at',
        'group_commission_type', 'group_commission_value', 'group_commission_earned',
        'staff_salary', 'deduct_on_failure', 'salary_deduction_earned',
        'manager_id', 'manager_commission_type', 'manager_commission_value', 'manager_commission_earned',
    ];

    protected $casts = [
        'period_start'          => 'date',
        'period_end'            => 'date',
        'verified_at'           => 'datetime',
        'deduct_on_failure'     => 'boolean',
        'group_commission_value'=> 'float',
        'group_commission_earned'=> 'float',
        'staff_salary'          => 'float',
        'salary_deduction_earned'=> 'float',
        'manager_commission_value'  => 'float',
        'manager_commission_earned' => 'float',
    ];

    public function user(): BelongsTo       { return $this->belongsTo(User::class); }
    public function assignedBy(): BelongsTo { return $this->belongsTo(User::class, 'assigned_by'); }
    public function verifiedBy(): BelongsTo { return $this->belongsTo(User::class, 'verified_by'); }
    public function manager(): BelongsTo    { return $this->belongsTo(User::class, 'manager_id'); }
    public function criteria(): HasMany     { return $this->hasMany(StaffTargetCriterion::class, 'target_id'); }

    public function grossCommission(): float
    {
        return (float) $this->criteria->sum('commission_earned')
             + (float) ($this->group_commission_earned ?? 0);
    }

    public function totalCommissionEarned(): float
    {
        return max(0, $this->grossCommission() - (float) ($this->salary_deduction_earned ?? 0));
    }

    public function calculateManagerCommission(bool $allGoalsMet): float
    {
        if (!$allGoalsMet || $this->manager_commission_type === 'none' || !$this->manager_id) {
            return 0.0;
        }
        $value = (float) ($this->manager_commission_value ?? 0);
        if ($this->manager_commission_type === 'fixed') {
            return round($value, 2);
        }
        return round($value / 100 * $this->grossCommission(), 2);
    }
}

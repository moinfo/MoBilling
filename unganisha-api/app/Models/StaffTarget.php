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
    ];

    protected $casts = [
        'period_start' => 'date',
        'period_end'   => 'date',
        'verified_at'  => 'datetime',
    ];

    public function user(): BelongsTo       { return $this->belongsTo(User::class); }
    public function assignedBy(): BelongsTo { return $this->belongsTo(User::class, 'assigned_by'); }
    public function verifiedBy(): BelongsTo { return $this->belongsTo(User::class, 'verified_by'); }
    public function criteria(): HasMany     { return $this->hasMany(StaffTargetCriterion::class, 'target_id'); }

    public function totalCommissionEarned(): float
    {
        return (float) $this->criteria->sum('commission_earned');
    }
}

<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class EmployeeOfMonthVote extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = ['tenant_id', 'cycle_id', 'voter_id', 'candidate_id', 'reason'];

    public function cycle(): BelongsTo
    {
        return $this->belongsTo(EmployeeOfMonthCycle::class, 'cycle_id');
    }

    public function voter(): BelongsTo
    {
        return $this->belongsTo(User::class, 'voter_id');
    }

    public function candidate(): BelongsTo
    {
        return $this->belongsTo(User::class, 'candidate_id');
    }
}

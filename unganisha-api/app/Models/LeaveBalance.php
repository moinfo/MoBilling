<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * A per-employee/type/year grant set by HR. Used/remaining days are NOT
 * stored here — computed on read from approved+non-cancelled LeaveRequests
 * (see LeaveRequestController::myBalance()) to avoid a second mutable
 * counter that can drift out of sync with the requests themselves.
 */
class LeaveBalance extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = ['tenant_id', 'user_id', 'leave_type_id', 'year', 'allocated_days'];

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function leaveType(): BelongsTo
    {
        return $this->belongsTo(LeaveType::class);
    }
}

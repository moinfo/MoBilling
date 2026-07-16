<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** A reply on a staff report — staff responding to feedback, or supervisor continuing the thread. */
class StaffReportReply extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = ['tenant_id', 'staff_report_id', 'user_id', 'message'];

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function report(): BelongsTo
    {
        return $this->belongsTo(StaffReport::class, 'staff_report_id');
    }
}

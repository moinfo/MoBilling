<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * A deduction charged to a staff member for a missing or late report.
 * Amounts come from StaffReportSettings; one row per person/type/period
 * (unique) so re-running the detector never double-charges.
 */
class StaffReportPenalty extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'user_id', 'report_type', 'penalty_type',
        'period_date', 'amount', 'staff_report_id', 'notes', 'waived',
    ];

    protected $casts = [
        'period_date' => 'date',
        'amount'      => 'decimal:2',
        'waived'      => 'boolean',
    ];

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}

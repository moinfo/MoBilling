<?php
namespace App\Models;
use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
class AttendanceSettings extends Model
{
    use HasUuids, BelongsToTenant;
    protected $fillable = [
        'tenant_id', 'check_in_time', 'check_out_time', 'saturday_check_out_time', 'penalties_enabled',
        'penalties_from',
        'penalty_absent', 'penalty_late', 'penalty_left_early', 'penalty_no_checkout', 'working_days',
        'exception_window_from', 'exception_window_to', 'exception_review_month',
    ];
    protected $casts = [
        'penalties_enabled' => 'boolean',
        'penalties_from' => 'date',
        'working_days'      => 'array',
        'exception_window_from' => 'date:Y-m-d',
        'exception_window_to' => 'date:Y-m-d',
        'exception_review_month' => 'date:Y-m-d',
    ];

    /**
     * Stored in a real SQL TIME column (unlike check_in_time/check_out_time,
     * which are plain H:i strings), so MySQL always returns it as "H:i:s".
     * Strip the seconds on read so the settings form can round-trip this
     * value unchanged through PUT /attendance/settings, whose validation
     * requires strict "H:i" — without this, saving any OTHER field (e.g.
     * the exception window) fails with a confusing generic error the
     * moment this field has ever been set.
     */
    public function getSaturdayCheckOutTimeAttribute($value)
    {
        return $value ? substr($value, 0, 5) : $value;
    }
}

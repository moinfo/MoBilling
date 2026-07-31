<?php
namespace App\Models;
use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
class AttendanceSettings extends Model
{
    use HasUuids, BelongsToTenant;
    protected $fillable = [
        'tenant_id', 'check_in_time', 'check_out_time', 'penalties_enabled',
        'penalties_from',
        'penalty_absent', 'penalty_late', 'penalty_left_early', 'penalty_no_checkout', 'working_days',
    ];
    protected $casts = [
        'penalties_enabled' => 'boolean',
        'penalties_from' => 'date',
        'working_days'      => 'array',
    ];
}

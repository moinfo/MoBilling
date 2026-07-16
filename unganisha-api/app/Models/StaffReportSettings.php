<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class StaffReportSettings extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'daily_target', 'weekly_target', 'monthly_target',
        'daily_deadline_time',
        'weekly_deadline_day', 'weekly_deadline_time',
        'monthly_deadline_day', 'monthly_deadline_time',
        'penalties_enabled', 'penalty_missing_daily', 'penalty_late',
        'penalty_missing_weekly', 'penalty_missing_monthly',
        'working_days',
    ];

    protected $casts = [
        'daily_target'         => 'integer',
        'weekly_target'        => 'integer',
        'monthly_target'       => 'integer',
        'weekly_deadline_day'  => 'integer',
        'monthly_deadline_day' => 'integer',
        'penalties_enabled'    => 'boolean',
        'working_days'         => 'array',
    ];
}
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
    ];

    protected $casts = [
        'daily_target'         => 'integer',
        'weekly_target'        => 'integer',
        'monthly_target'       => 'integer',
        'weekly_deadline_day'  => 'integer',
        'monthly_deadline_day' => 'integer',
    ];
}
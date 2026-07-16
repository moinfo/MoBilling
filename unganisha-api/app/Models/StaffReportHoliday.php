<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/** A day the office is closed — daily reports aren't required (and aren't charged) on it. */
class StaffReportHoliday extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = ['tenant_id', 'date', 'name'];
    protected $casts = ['date' => 'date'];
}

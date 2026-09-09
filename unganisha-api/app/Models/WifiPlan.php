<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class WifiPlan extends Model
{
    use HasFactory, HasUuids, SoftDeletes, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'mikrotik_router_id', 'name', 'duration_value', 'duration_unit',
        'price', 'hotspot_profile', 'is_active',
    ];

    protected $casts = [
        'price'      => 'decimal:2',
        'is_active'  => 'boolean',
    ];

    public function router()
    {
        return $this->belongsTo(MikrotikRouter::class, 'mikrotik_router_id');
    }

    /** Duration converted to whole seconds, for the RouterOS "limit-uptime" field. */
    public function durationSeconds(): int
    {
        $perUnit = match ($this->duration_unit) {
            'hours' => 3600,
            'days'  => 86400,
            'weeks' => 604800,
        };

        return $this->duration_value * $perUnit;
    }
}

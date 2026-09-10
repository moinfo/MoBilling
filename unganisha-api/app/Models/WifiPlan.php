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
        'tenant_id', 'mikrotik_router_id', 'name', 'duration_value', 'duration_unit', 'data_cap_mb', 'speed_limit_mbps',
        'price', 'hotspot_profile', 'is_active',
    ];

    protected $casts = [
        'price'            => 'decimal:2',
        'speed_limit_mbps' => 'decimal:2',
        'is_active'        => 'boolean',
    ];

    public function router()
    {
        return $this->belongsTo(MikrotikRouter::class, 'mikrotik_router_id');
    }

    /**
     * Duration converted to whole seconds, for the RouterOS "limit-uptime"
     * field. Null = no time limit at all (a pure data-cap plan, e.g. "5GB,
     * good until it's used up") — StoreWifiPlanRequest guarantees a plan
     * always has at least one of {duration, data_cap_mb} set.
     */
    public function durationSeconds(): ?int
    {
        if (!$this->duration_value || !$this->duration_unit) {
            return null;
        }

        $perUnit = match ($this->duration_unit) {
            'hours' => 3600,
            'days'  => 86400,
            'weeks' => 604800,
        };

        return $this->duration_value * $perUnit;
    }

    /** null = unlimited data. */
    public function dataCapBytes(): ?int
    {
        return $this->data_cap_mb ? $this->data_cap_mb * 1024 * 1024 : null;
    }

    /**
     * RouterOS hotspot user "rate-limit" string (e.g. "2M/2M") — symmetric
     * up/down. Mainly a sharing deterrent: tethering this to several people
     * splits a capped pipe, so it gets noticeably slow fast rather than
     * silently working fine for everyone. Null = unlimited.
     */
    public function rateLimitString(): ?string
    {
        if (!$this->speed_limit_mbps) {
            return null;
        }

        $mbps = rtrim(rtrim((string) $this->speed_limit_mbps, '0'), '.');
        return "{$mbps}M/{$mbps}M";
    }
}

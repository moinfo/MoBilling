<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * A physical office/site staff self-check-in is geofenced against — see
 * AttendanceController::checkIn(). `radius_meters` needs headroom: phone GPS
 * is rarely accurate to better than 10-20m indoors.
 */
class WorkLocation extends Model
{
    use HasUuids, SoftDeletes, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'name', 'latitude', 'longitude', 'radius_meters', 'is_active',
    ];

    protected $casts = [
        'latitude' => 'decimal:7',
        'longitude' => 'decimal:7',
        'is_active' => 'boolean',
    ];

    public function staff()
    {
        return $this->hasMany(User::class);
    }

    /**
     * Great-circle distance in meters (haversine) from this location to a
     * point. Earth radius in meters; good enough for a few-hundred-meter
     * geofence — no need for anything more precise than a sphere here.
     */
    public function distanceMetersTo(float $latitude, float $longitude): float
    {
        $earthRadius = 6371000;

        $latFrom = deg2rad((float) $this->latitude);
        $lonFrom = deg2rad((float) $this->longitude);
        $latTo = deg2rad($latitude);
        $lonTo = deg2rad($longitude);

        $latDelta = $latTo - $latFrom;
        $lonDelta = $lonTo - $lonFrom;

        $a = sin($latDelta / 2) ** 2
            + cos($latFrom) * cos($latTo) * sin($lonDelta / 2) ** 2;
        $c = 2 * atan2(sqrt($a), sqrt(1 - $a));

        return $earthRadius * $c;
    }

    public function isWithinRadius(float $latitude, float $longitude): bool
    {
        return $this->distanceMetersTo($latitude, $longitude) <= $this->radius_meters;
    }
}

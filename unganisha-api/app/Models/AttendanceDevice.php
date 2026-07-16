<?php
namespace App\Models;
use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
class AttendanceDevice extends Model
{
    use HasUuids, BelongsToTenant;
    protected $fillable = ['tenant_id', 'name', 'token', 'is_active', 'last_event_at'];
    protected $casts = ['is_active' => 'boolean', 'last_event_at' => 'datetime'];
}

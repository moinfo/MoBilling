<?php
namespace App\Models;
use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
class AttendanceDeviceEvent extends Model
{
    use HasUuids, BelongsToTenant;
    protected $fillable = [
        'tenant_id', 'attendance_device_id', 'content_type',
        'employee_no', 'event_time', 'payload', 'parsed', 'processed',
    ];
    protected $casts = ['parsed' => 'array', 'event_time' => 'datetime', 'processed' => 'boolean'];
}

<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class MikrotikLog extends Model
{
    use HasUuids;

    protected $fillable = [
        'tenant_id', 'mikrotik_router_id', 'action', 'request', 'response', 'status', 'error',
    ];

    protected $casts = [
        'request'  => 'array',
        'response' => 'array',
    ];

    public function router()
    {
        return $this->belongsTo(MikrotikRouter::class, 'mikrotik_router_id');
    }
}

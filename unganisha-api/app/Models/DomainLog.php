<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class DomainLog extends Model
{
    use HasUuids;

    protected $fillable = [
        'tenant_id', 'domain_id', 'action', 'request', 'response', 'status', 'error',
    ];

    protected $casts = [
        'request'  => 'array',
        'response' => 'array',
    ];

    public function domain()
    {
        return $this->belongsTo(Domain::class);
    }
}

<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class WhatsappRenewalSession extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'client_id', 'assisted_by_user_id', 'items', 'flow', 'language', 'state', 'confirmed_at', 'attempts', 'phone', 'expires_at', 'flow_expires_at',
    ];

    protected $casts = [
        'items' => 'array',
        'state' => 'array',
        'confirmed_at' => 'datetime',
        'expires_at' => 'datetime',
        'flow_expires_at' => 'datetime',
    ];

    public function isExpired(): bool
    {
        return $this->expires_at->isPast();
    }
}

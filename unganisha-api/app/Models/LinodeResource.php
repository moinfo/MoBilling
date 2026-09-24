<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class LinodeResource extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'linode_account_id', 'type', 'remote_id', 'label', 'status', 'region', 'plan',
        'ipv4', 'ipv6', 'tags', 'meta', 'client_id', 'client_subscription_id', 'domain_id', 'synced_at',
    ];

    protected $casts = [
        'ipv4' => 'array', 'tags' => 'array', 'meta' => 'array', 'synced_at' => 'datetime',
    ];

    public function account()
    {
        return $this->belongsTo(LinodeAccount::class, 'linode_account_id');
    }

    public function client()
    {
        return $this->belongsTo(Client::class);
    }
}

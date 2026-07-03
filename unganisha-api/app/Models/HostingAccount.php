<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class HostingAccount extends Model
{
    use HasUuids, BelongsToTenant;

    public const STATUSES = ['pending', 'active', 'suspended', 'terminated', 'failed'];

    protected $fillable = [
        'tenant_id', 'client_subscription_id', 'server_id', 'domain',
        'cpanel_username', 'package', 'status', 'last_synced_at', 'meta', 'legacy_id',
    ];

    protected $casts = [
        'meta'           => 'array',
        'last_synced_at' => 'datetime',
    ];

    public function subscription()
    {
        return $this->belongsTo(ClientSubscription::class, 'client_subscription_id');
    }

    public function server()
    {
        return $this->belongsTo(Server::class);
    }

    public function logs()
    {
        return $this->hasMany(ProvisioningLog::class)->latest();
    }
}

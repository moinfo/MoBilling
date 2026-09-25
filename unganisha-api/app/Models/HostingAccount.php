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

    /**
     * Why is this account suspended? Never guess "unpaid invoices" for everything:
     * 'bandwidth' = usage at/over the plan limit (WHM suspends those automatically),
     * 'billing' = the linked subscription itself is suspended (non-payment flow),
     * 'other' = suspended for a reason we can't tell (staff/manual/abuse).
     * Null when the account is not suspended.
     */
    public function suspensionReason(): ?string
    {
        if ($this->status !== 'suspended') {
            return null;
        }
        $used = (float) ($this->meta['bw_used_bytes'] ?? 0);
        $limit = (float) ($this->meta['bw_limit_bytes'] ?? 0);
        if ($limit > 0 && $used >= $limit) {
            return 'bandwidth';
        }
        $sub = $this->relationLoaded('subscription') ? $this->subscription : $this->subscription()->withoutGlobalScopes()->first();
        if ($sub && $sub->status === 'suspended') {
            return 'billing';
        }

        return 'other';
    }

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

    public function backupSetting()
    {
        return $this->hasOne(HostingAccountBackupSetting::class);
    }
}

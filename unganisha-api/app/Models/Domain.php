<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class Domain extends Model
{
    use HasUuids, BelongsToTenant;

    public const STATUSES = ['pending', 'active', 'expired', 'transferred_out', 'cancelled', 'failed'];

    protected $fillable = [
        'tenant_id', 'client_id', 'registrar_account_id', 'name', 'status',
        'registrant_handle', 'admin_handle', 'nsset_handle', 'keyset_handle',
        'registered_at', 'expires_at', 'auto_renew', 'client_subscription_id',
        'epp_auth_info', 'meta', 'legacy_id',
    ];

    protected $casts = [
        'registered_at' => 'date',
        'expires_at'    => 'date',
        'auto_renew'    => 'boolean',
        'epp_auth_info' => 'encrypted',
        'meta'          => 'array',
    ];

    protected $hidden = ['epp_auth_info'];

    public function client()
    {
        return $this->belongsTo(Client::class);
    }

    public function registrarAccount()
    {
        return $this->belongsTo(RegistrarAccount::class);
    }

    public function subscription()
    {
        return $this->belongsTo(ClientSubscription::class, 'client_subscription_id');
    }

    public function logs()
    {
        return $this->hasMany(DomainLog::class)->latest();
    }
}

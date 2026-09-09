<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class MikrotikRouter extends Model
{
    use HasFactory, HasUuids, SoftDeletes, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'name', 'host', 'local_login_host', 'api_port', 'username', 'password', 'use_tls',
        'payment_mode', 'is_active', 'last_tested_at', 'last_test_status', 'last_test_message',
    ];

    protected $hidden = ['password'];

    // Eloquent doesn't reflect DB column defaults until a refresh — set
    // them here too so a freshly create()'d instance already has real
    // values (bit us once: RouterOsService got use_tls=null, not false).
    protected $attributes = [
        'api_port'     => 8728,
        'use_tls'      => false,
        'payment_mode' => 'self_managed',
        'is_active'    => true,
    ];

    protected $casts = [
        'password'       => 'encrypted',
        'use_tls'        => 'boolean',
        'is_active'      => 'boolean',
        'last_tested_at' => 'datetime',
    ];

    public function plans()
    {
        return $this->hasMany(WifiPlan::class);
    }

    public function purchases()
    {
        return $this->hasMany(WifiVoucherPurchase::class);
    }

    public function logs()
    {
        return $this->hasMany(MikrotikLog::class);
    }
}

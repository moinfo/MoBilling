<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class Server extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'name', 'hostname', 'port', 'username', 'api_token',
        'nameservers', 'type', 'is_active', 'verify_ssl', 'legacy_id',
    ];

    protected $casts = [
        'api_token'   => 'encrypted',
        'nameservers' => 'array',
        'is_active'   => 'boolean',
        'verify_ssl'  => 'boolean',
        'port'        => 'integer',
    ];

    protected $hidden = ['api_token'];

    public function hostingAccounts()
    {
        return $this->hasMany(HostingAccount::class);
    }
}

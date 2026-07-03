<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * A registrar accreditation. tenant_id NULL = the platform account, shared by
 * all tenants as fallback. Deliberately NOT using BelongsToTenant — its global
 * scope would hide the platform row; scoping is done explicitly in the
 * DomainRegistrarManager resolver.
 */
class RegistrarAccount extends Model
{
    use HasUuids;

    protected $fillable = [
        'tenant_id', 'name', 'driver', 'endpoint_url', 'registrar_id',
        'credentials', 'is_active', 'is_sandbox',
    ];

    protected $casts = [
        'credentials' => 'encrypted:array',
        'is_active'   => 'boolean',
        'is_sandbox'  => 'boolean',
    ];

    protected $hidden = ['credentials'];

    public function domains()
    {
        return $this->hasMany(Domain::class);
    }
}

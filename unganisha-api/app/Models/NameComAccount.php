<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/** Tenant's Name.com API credentials (one per tenant). The token is write-only. */
class NameComAccount extends Model
{
    use HasUuids, BelongsToTenant;

    protected $table = 'namecom_accounts';

    protected $fillable = [
        'tenant_id', 'username', 'token', 'token_hint', 'is_sandbox', 'status', 'status_message', 'last_verified_at',
    ];

    protected $casts = [
        'token'            => 'encrypted',
        'is_sandbox'       => 'boolean',
        'last_verified_at' => 'datetime',
    ];

    protected $hidden = ['token'];

    public function toSafeArray(): array
    {
        return [
            'id'               => $this->id,
            'username'         => $this->username,
            'token_hint'       => $this->token_hint ? '••••' . $this->token_hint : null,
            'is_sandbox'       => $this->is_sandbox,
            'status'           => $this->status,
            'status_message'   => $this->status_message,
            'last_verified_at' => $this->last_verified_at,
        ];
    }
}

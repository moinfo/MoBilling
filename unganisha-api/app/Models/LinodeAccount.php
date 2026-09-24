<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class LinodeAccount extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'label', 'token', 'token_hint', 'soa_email', 'status', 'status_message',
        'last_verified_at', 'last_synced_at',
    ];

    protected $casts = [
        'token'            => 'encrypted',
        'last_verified_at' => 'datetime',
        'last_synced_at'   => 'datetime',
    ];

    /** The token must never leave the server — not even encrypted. */
    protected $hidden = ['token'];

    public function resources()
    {
        return $this->hasMany(LinodeResource::class);
    }

    /** Safe public representation. */
    public function toSafeArray(): array
    {
        return [
            'id'               => $this->id,
            'label'            => $this->label,
            'token_hint'       => $this->token_hint ? '••••' . $this->token_hint : null,
            'soa_email'        => $this->soa_email,
            'status'           => $this->status,
            'status_message'   => $this->status_message,
            'last_verified_at' => $this->last_verified_at,
            'last_synced_at'   => $this->last_synced_at,
        ];
    }
}

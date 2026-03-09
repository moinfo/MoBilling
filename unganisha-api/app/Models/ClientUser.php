<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

class ClientUser extends Authenticatable
{
    use HasUuids, SoftDeletes, HasApiTokens, Notifiable;

    protected $fillable = [
        'client_id', 'tenant_id', 'name', 'email',
        'password', 'phone', 'role', 'is_active',
    ];

    protected $hidden = [
        'password',
    ];

    protected function casts(): array
    {
        return [
            'password' => 'hashed',
            'is_active' => 'boolean',
            'last_login_at' => 'datetime',
        ];
    }

    public function client()
    {
        return $this->belongsTo(Client::class);
    }

    public function tenant()
    {
        return $this->belongsTo(Tenant::class);
    }

    public function isPortalAdmin(): bool
    {
        return $this->role === 'admin';
    }
}

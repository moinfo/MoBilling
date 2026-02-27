<?php

namespace App\Models;

use App\Notifications\ResetPasswordNotification;
use Illuminate\Auth\Passwords\CanResetPassword;
use Illuminate\Contracts\Auth\CanResetPassword as CanResetPasswordContract;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable implements CanResetPasswordContract
{
    use HasFactory, Notifiable, HasUuids, SoftDeletes, HasApiTokens, CanResetPassword;

    protected $fillable = [
        'tenant_id', 'name', 'email', 'password',
        'phone', 'role', 'role_id', 'is_active',
    ];

    protected $hidden = [
        'password',
        'remember_token',
    ];

    protected function casts(): array
    {
        return [
            'password' => 'hashed',
            'is_active' => 'boolean',
        ];
    }

    public function isSuperAdmin(): bool
    {
        return $this->role === 'super_admin';
    }

    public function tenant()
    {
        return $this->belongsTo(Tenant::class);
    }

    public function role()
    {
        return $this->belongsTo(Role::class);
    }

    /**
     * Check if the user has a specific permission via their role.
     * Super admins bypass all permission checks.
     */
    public function hasPermission(string $name): bool
    {
        if ($this->isSuperAdmin()) {
            return true;
        }

        return in_array($name, $this->getPermissionNames());
    }

    /**
     * Check if the user has any of the given permissions.
     */
    public function hasAnyPermission(array $names): bool
    {
        if ($this->isSuperAdmin()) {
            return true;
        }

        $userPerms = $this->getPermissionNames();

        foreach ($names as $name) {
            if (in_array($name, $userPerms)) {
                return true;
            }
        }

        return false;
    }

    /**
     * Get cached list of permission names for this user's role.
     */
    public function getPermissionNames(): array
    {
        if ($this->isSuperAdmin()) {
            return [];
        }

        // Cache per request using a property
        if (!isset($this->cachedPermissionNames)) {
            $this->cachedPermissionNames = $this->role_id
                ? $this->role()->with('permissions')->first()?->permissions->pluck('name')->toArray() ?? []
                : [];
        }

        return $this->cachedPermissionNames;
    }

    private $cachedPermissionNames;

    public function sendPasswordResetNotification($token): void
    {
        $this->notify(new ResetPasswordNotification($token));
    }
}

<?php

namespace App\Models;

use App\Notifications\ResetPasswordNotification;
use App\Traits\HasTwoFactorAuth;
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
    use HasFactory, Notifiable, HasUuids, SoftDeletes, HasApiTokens, CanResetPassword, HasTwoFactorAuth;

    protected $fillable = [
        'tenant_id', 'name', 'email', 'password',
        'phone', 'role', 'role_id', 'is_active', 'supervisor_id', 'device_employee_no',
    ];

    protected $hidden = [
        'password',
        'remember_token',
        'two_factor_secret',
        'two_factor_recovery_codes',
    ];

    protected function casts(): array
    {
        return [
            'password' => 'hashed',
            'is_active' => 'boolean',
            'two_factor_secret' => 'encrypted',
            'two_factor_recovery_codes' => 'encrypted:array',
            'two_factor_confirmed_at' => 'datetime',
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
     * Active staff in [tenantId] whose role grants [permission] — the "who
     * should hear about this" resolver for business-event notifications that
     * have no single obvious recipient (an assignee, a supervisor). Mirrors
     * the query TicketController::staffToNotify already used ad hoc, pulled
     * out here so new notification call sites don't each reinvent it.
     */
    public static function withPermission(string $tenantId, string $permission)
    {
        return static::withoutGlobalScopes()
            ->where('tenant_id', $tenantId)
            ->where('is_active', true)
            ->whereHas('role.permissions', fn ($q) => $q->where('name', $permission))
            ->get();
    }

    public function supervisor()
    {
        return $this->belongsTo(User::class, 'supervisor_id');
    }

    public function subordinates()
    {
        return $this->hasMany(User::class, 'supervisor_id');
    }

    public function employeeProfile()
    {
        return $this->hasOne(EmployeeProfile::class);
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
     * Get cached list of permission names for this user's role, narrowed to
     * their tenant's paid subscription plan ceiling (if any).
     */
    public function getPermissionNames(): array
    {
        if ($this->isSuperAdmin()) {
            return [];
        }

        // Cache per request using a property
        if (!isset($this->cachedPermissionNames)) {
            $roleNames = $this->role_id
                ? $this->role()->with('permissions')->first()?->permissions->pluck('name')->toArray() ?? []
                : [];

            $planCeiling = $this->planPermissionCeiling();
            $this->cachedPermissionNames = $planCeiling === null
                ? $roleNames
                : array_values(array_intersect($roleNames, $planCeiling));
        }

        return $this->cachedPermissionNames;
    }

    /**
     * Permission names allowed by the tenant's current paid subscription
     * plan, or null if no ceiling should apply. Trial tenants get full
     * (unrestricted) access regardless of role permissions, so evaluators
     * see the whole product before paying — the ceiling only kicks in once
     * a plan is actually purchased and active. A plan with zero permissions
     * configured (e.g. a brand-new plan an admin hasn't set up yet) fails
     * OPEN, not closed — never silently locks a paying tenant out of
     * everything just because nobody attached permissions to their plan.
     */
    private function planPermissionCeiling(): ?array
    {
        $tenant = $this->tenant;
        if (!$tenant || !$tenant->hasActiveSubscription()) {
            return null;
        }

        $planNames = $tenant->activeSubscription?->plan?->permissions->pluck('name')->toArray();

        return empty($planNames) ? null : $planNames;
    }

    private $cachedPermissionNames;

    public function sendPasswordResetNotification($token): void
    {
        $this->notify(new ResetPasswordNotification($token));
    }
}

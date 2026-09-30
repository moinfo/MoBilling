<?php

namespace App\Traits;

use App\Models\Tenant;

trait BelongsToTenant
{
    protected static function bootBelongsToTenant(): void
    {
        static::creating(function ($model) {
            // Only fill it in — never overwrite a tenant_id the caller
            // already set explicitly. Without this guard, any authenticated
            // actor creating a row on another tenant's behalf (a superadmin
            // resetting a tenant user's password, ResellerProvisioningService
            // duplicating rows onto a brand-new tenant, etc.) would silently
            // have that tenant_id clobbered with their OWN tenant_id (or
            // null, for a superadmin with none) — see the communication_logs
            // NOT NULL violation this caused for LogNotification's explicit
            // cross-tenant tenant_id.
            if (auth()->check() && !$model->tenant_id) {
                $model->tenant_id = auth()->user()->tenant_id;
            }
        });

        static::addGlobalScope('tenant', function ($query) {
            if (auth()->check()) {
                $query->where($query->getModel()->getTable() . '.tenant_id', auth()->user()->tenant_id);
            }
        });
    }

    public function tenant()
    {
        return $this->belongsTo(Tenant::class);
    }
}

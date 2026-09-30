<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * A client's application to become a white-label reseller. See the
 * migration for the full picture; ResellerProvisioningService turns an
 * approved application into a real Tenant.
 */
class ResellerApplication extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'client_id', 'requested_domain', 'brand_name', 'categories',
        'contact_name', 'contact_email', 'contact_phone',
        'status', 'staff_note', 'decided_by', 'decided_at', 'provisioned_tenant_id',
    ];

    protected $casts = [
        'categories'  => 'array',
        'decided_at'  => 'datetime',
    ];

    public const CATEGORIES = ['domain', 'hosting', 'email', 'linode'];

    public function client()
    {
        return $this->belongsTo(Client::class);
    }

    public function decidedBy()
    {
        return $this->belongsTo(User::class, 'decided_by');
    }

    public function provisionedTenant()
    {
        return $this->belongsTo(Tenant::class, 'provisioned_tenant_id');
    }
}

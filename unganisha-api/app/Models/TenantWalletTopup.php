<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/** A reseller tenant's self-service Pesapal wallet top-up request. See the migration. */
class TenantWalletTopup extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'requested_by', 'amount', 'status',
        'order_tracking_id', 'pesapal_redirect_url', 'payment_status_description',
        'confirmation_code', 'payment_method_used', 'gateway_response', 'completed_at',
    ];

    protected $casts = [
        'amount'           => 'decimal:2',
        'gateway_response' => 'array',
        'completed_at'     => 'datetime',
    ];
}

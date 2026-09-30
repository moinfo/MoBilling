<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Ledger row for a white-label reseller tenant's prepaid wallet — see
 * TenantWalletService. Deliberately NOT using BelongsToTenant (like
 * RegistrarAccount/DomainTld): a row is legitimately written by Moinfotech's
 * own staff acting on a DIFFERENT tenant's wallet (the staff-confirmed
 * "paid outside" top-up) or by the webhook handler with no authenticated
 * user at all — BelongsToTenant's creating() hook would silently force
 * tenant_id to the acting/absent auth user's own tenant instead of the
 * explicit tenant_id every write here always passes. Every read already
 * filters by an explicit tenant_id (TenantWalletController, Reseller
 * ApplicationController::walletShow), so no query relied on the global scope.
 */
class TenantWalletTransaction extends Model
{
    use HasUuids;

    protected $fillable = [
        'tenant_id', 'type', 'amount', 'balance_after', 'reference',
        'related_type', 'related_id', 'created_by', 'notes',
    ];

    protected $casts = [
        'amount'        => 'decimal:2',
        'balance_after' => 'decimal:2',
    ];

    public function createdBy()
    {
        return $this->belongsTo(User::class, 'created_by');
    }
}

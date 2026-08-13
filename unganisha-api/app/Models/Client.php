<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Notifications\Notifiable;

class Client extends Model
{
    use HasFactory, HasUuids, SoftDeletes, BelongsToTenant, Notifiable;

    protected $fillable = [
        'tenant_id', 'name', 'email', 'phone',
        'address', 'tax_id', 'status', 'notes', 'legacy_id', 'credit_balance',
        'first_name', 'last_name', 'company_name',
        'address_1', 'address_2', 'city', 'state', 'postcode', 'country',
    ];

    public function documents()
    {
        return $this->hasMany(Document::class);
    }

    public function subscriptions()
    {
        return $this->hasMany(ClientSubscription::class);
    }

    public function contacts()
    {
        return $this->hasMany(ClientContact::class);
    }

    /**
     * Reseller status is never a stored flag — it's derived live from an
     * active subscription to the "Reseller Membership" product, so the
     * existing recurring-billing/auto-suspend engine is the single source of
     * truth (non-payment silently revokes it, no separate code path needed).
     */
    public function resellerSubscription(): ?ClientSubscription
    {
        return $this->subscriptions()
            ->withoutGlobalScopes()
            ->where('status', 'active')
            ->whereHas('productService', fn ($q) => $q->withoutGlobalScopes()->where('name', 'Reseller Membership'))
            ->first();
    }

    public function isReseller(): bool
    {
        return $this->resellerSubscription() !== null;
    }
}

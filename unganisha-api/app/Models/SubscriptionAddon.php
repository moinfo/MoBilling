<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class SubscriptionAddon extends Model
{
    use HasFactory, HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'client_subscription_id', 'product_addon_id',
        'name', 'price', 'billing_cycle', 'tax_percent', 'status',
    ];

    protected $casts = [
        'price' => 'decimal:2',
        'tax_percent' => 'decimal:2',
    ];

    public function subscription()
    {
        return $this->belongsTo(ClientSubscription::class, 'client_subscription_id');
    }

    public function productAddon()
    {
        return $this->belongsTo(ProductAddon::class);
    }

    public function scopeActive($query)
    {
        return $query->where('status', 'active');
    }
}

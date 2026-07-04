<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class SubscriptionConfigOption extends Model
{
    use HasFactory, HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'client_subscription_id', 'config_option_id', 'choice_id',
        'label', 'unit_price', 'quantity', 'billing_cycle', 'tax_percent', 'status',
    ];

    protected $casts = [
        'unit_price' => 'decimal:2',
        'tax_percent' => 'decimal:2',
        'quantity' => 'integer',
    ];

    public function subscription()
    {
        return $this->belongsTo(ClientSubscription::class, 'client_subscription_id');
    }

    public function configOption()
    {
        return $this->belongsTo(ConfigOption::class, 'config_option_id');
    }

    public function scopeActive($query)
    {
        return $query->where('status', 'active');
    }
}

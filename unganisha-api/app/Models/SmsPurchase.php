<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class SmsPurchase extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'user_id', 'sms_quantity', 'price_per_sms',
        'total_amount', 'package_name', 'receipt_number', 'status',
        'order_tracking_id', 'pesapal_redirect_url',
        'payment_status_description', 'confirmation_code',
        'payment_method_used', 'gateway_response', 'completed_at',
    ];

    protected $casts = [
        'price_per_sms' => 'decimal:2',
        'total_amount' => 'decimal:2',
        'gateway_response' => 'array',
        'completed_at' => 'datetime',
    ];

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}

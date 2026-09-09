<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Notifications\Notifiable;

class WifiVoucherPurchase extends Model
{
    use HasFactory, HasUuids, BelongsToTenant, Notifiable;

    protected $fillable = [
        'tenant_id', 'mikrotik_router_id', 'wifi_plan_id', 'customer_phone', 'customer_name',
        'amount', 'commission_amount', 'net_amount', 'status', 'order_tracking_id', 'pesapal_redirect_url',
        'payment_status_description', 'confirmation_code', 'payment_method_used',
        'gateway_response', 'completed_at', 'hotspot_username', 'hotspot_password',
        'voucher_expires_at', 'meta',
        'settled_at', 'settlement_method', 'settlement_reference', 'settlement_notes', 'settled_by',
    ];

    protected $casts = [
        'amount'              => 'decimal:2',
        'commission_amount'   => 'decimal:2',
        'net_amount'          => 'decimal:2',
        'gateway_response'    => 'array',
        'meta'                => 'array',
        'completed_at'        => 'datetime',
        'voucher_expires_at'  => 'datetime',
        'settled_at'          => 'datetime',
    ];

    public function router()
    {
        return $this->belongsTo(MikrotikRouter::class, 'mikrotik_router_id');
    }

    public function plan()
    {
        return $this->belongsTo(WifiPlan::class, 'wifi_plan_id');
    }

    /** SmsChannel/WhatsAppChannel expect ->phone on the notifiable. */
    public function getPhoneAttribute(): ?string
    {
        return $this->customer_phone;
    }
}

<?php

namespace App\Models;

use App\Services\Mikrotik\RouterOsService;
use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Notifications\Notifiable;
use Illuminate\Support\Facades\Log;

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

    /**
     * Live data/time usage for this voucher, queried straight from the
     * router — MoBilling doesn't store a running total anywhere itself
     * (see ProvisionWifiVoucherJob). Shared by the public balance-check
     * endpoint and the admin voucher-sales list so both read the exact
     * same numbers the same way.
     */
    public function liveUsage(): array
    {
        $this->loadMissing(['router', 'plan']);

        $usage = null;
        if ($this->hotspot_username && $this->router) {
            try {
                $usage = (new RouterOsService($this->router))->getHotspotUserUsage($this->hotspot_username);
            } catch (\Throwable $e) {
                Log::warning("WiFi usage check failed for purchase {$this->id}: {$e->getMessage()}");
            }
        }

        $usedBytes = $usage ? $usage['bytes_in'] + $usage['bytes_out'] : null;
        $dataCapMb = $this->plan?->data_cap_mb;
        $durationSeconds = $this->plan?->durationSeconds();
        $usedSeconds = $usage['uptime_seconds'] ?? null;

        return [
            'data_cap_mb'       => $dataCapMb,
            'data_used_mb'      => $usedBytes !== null ? round($usedBytes / 1048576, 1) : null,
            'data_remaining_mb' => ($dataCapMb && $usedBytes !== null)
                ? max(0, round($dataCapMb - $usedBytes / 1048576, 1))
                : null,
            'duration_seconds'       => $durationSeconds,
            'time_used_seconds'      => $usedSeconds,
            'time_remaining_seconds' => ($durationSeconds !== null && $usedSeconds !== null)
                ? max(0, $durationSeconds - $usedSeconds)
                : null,
            'router_reachable' => $usage !== null,
        ];
    }
}

<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * A public, unauthenticated self-hosted license purchase via Pesapal — the
 * customer isn't a MoBilling tenant, they're buying a License to run on
 * their own server. PesapalWebhookController auto-issues the License once
 * the IPN confirms payment; see processLicensePurchaseCompleted() there.
 */
class LicensePurchase extends Model
{
    use HasUuids;

    protected $fillable = [
        'customer_name', 'customer_email', 'customer_phone',
        'product', 'billing_period', 'amount', 'status', 'license_id',
        'order_tracking_id', 'pesapal_redirect_url', 'payment_status_description',
        'confirmation_code', 'payment_method_used', 'gateway_response', 'completed_at',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
        'gateway_response' => 'array',
        'completed_at' => 'datetime',
    ];

    public function license(): BelongsTo
    {
        return $this->belongsTo(License::class);
    }
}

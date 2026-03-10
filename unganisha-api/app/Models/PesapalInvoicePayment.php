<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class PesapalInvoicePayment extends Model
{
    use HasFactory, HasUuids;

    protected $table = 'pesapal_invoice_payments';

    protected $fillable = [
        'tenant_id', 'document_id', 'merchant_reference', 'order_tracking_id',
        'pesapal_redirect_url', 'amount', 'currency', 'status',
        'payment_status_description', 'payment_method_used',
        'confirmation_code', 'gateway_response', 'completed_at',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
        'gateway_response' => 'array',
        'completed_at' => 'datetime',
    ];

    public function tenant()
    {
        return $this->belongsTo(Tenant::class);
    }

    public function document()
    {
        return $this->belongsTo(Document::class);
    }
}

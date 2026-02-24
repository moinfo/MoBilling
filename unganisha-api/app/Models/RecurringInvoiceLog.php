<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class RecurringInvoiceLog extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'client_id', 'product_service_id', 'document_id',
        'next_bill_date', 'invoice_created_at', 'reminders_sent',
    ];

    protected $casts = [
        'next_bill_date' => 'date',
        'invoice_created_at' => 'datetime',
        'reminders_sent' => 'array',
    ];

    public function client()
    {
        return $this->belongsTo(Client::class);
    }

    public function productService()
    {
        return $this->belongsTo(ProductService::class);
    }

    public function document()
    {
        return $this->belongsTo(Document::class);
    }
}

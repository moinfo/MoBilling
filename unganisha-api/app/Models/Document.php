<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Document extends Model
{
    use HasFactory, HasUuids, SoftDeletes, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'client_id', 'type', 'document_number',
        'parent_id', 'date', 'due_date', 'subtotal', 'discount_amount',
        'tax_amount', 'total', 'notes', 'status', 'overdue_stage', 'created_by', 'legacy_id',
    ];

    protected $casts = [
        'date' => 'date',
        'due_date' => 'date',
        'subtotal' => 'decimal:2',
        'discount_amount' => 'decimal:2',
        'tax_amount' => 'decimal:2',
        'total' => 'decimal:2',
    ];

    public function client()
    {
        return $this->belongsTo(Client::class);
    }

    public function items()
    {
        return $this->hasMany(DocumentItem::class);
    }

    public function payments()
    {
        return $this->hasMany(PaymentIn::class);
    }

    public function refunds()
    {
        return $this->hasMany(Refund::class);
    }

    public function parent()
    {
        return $this->belongsTo(Document::class, 'parent_id');
    }

    public function children()
    {
        return $this->hasMany(Document::class, 'parent_id');
    }

    public function createdBy()
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function communicationLogs()
    {
        return $this->hasMany(CommunicationLog::class, 'client_id', 'client_id')
            ->whereRaw("JSON_EXTRACT(metadata, '$.document_id') = ?", [$this->id]);
    }

    public function getPaidAmountAttribute()
    {
        // Net paid = payments received − refunds returned. A refund correctly drops
        // the paid amount so the invoice reverts to partial/sent and balance_due rises.
        //
        // Prefer an eager-loaded sum (->withSum('payments', 'amount')) to avoid
        // running one SUM query per document when listing many invoices. Refunds
        // are rare, so ->withSum('refunds', 'amount') is optional: when it is not
        // eager-loaded we fall back to a per-row query only for the refund side.
        if (array_key_exists('payments_sum_amount', $this->attributes)) {
            $paid = (float) ($this->attributes['payments_sum_amount'] ?? 0);
            $refunded = array_key_exists('refunds_sum_amount', $this->attributes)
                ? (float) ($this->attributes['refunds_sum_amount'] ?? 0)
                : (float) $this->refunds()->sum('amount');

            return round($paid - $refunded, 2);
        }

        return round((float) $this->payments()->sum('amount') - (float) $this->refunds()->sum('amount'), 2);
    }

    public function getBalanceDueAttribute()
    {
        return $this->total - $this->paid_amount;
    }
}

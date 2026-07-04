<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Refund extends Model
{
    use HasFactory, HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'document_id', 'client_id', 'amount',
        'method', 'reference', 'notes', 'refunded_by',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
    ];

    public function document()
    {
        return $this->belongsTo(Document::class);
    }

    public function client()
    {
        return $this->belongsTo(Client::class);
    }

    public function refundedBy()
    {
        return $this->belongsTo(User::class, 'refunded_by');
    }
}

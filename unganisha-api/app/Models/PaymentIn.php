<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class PaymentIn extends Model
{
    use HasFactory, HasUuids, BelongsToTenant;

    protected $table = 'payments_in';

    protected $fillable = [
        'tenant_id', 'document_id', 'amount', 'payment_date',
        'payment_method', 'reference', 'notes',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
        'payment_date' => 'date',
    ];

    public function document()
    {
        return $this->belongsTo(Document::class);
    }
}

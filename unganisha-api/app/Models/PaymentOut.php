<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class PaymentOut extends Model
{
    use HasFactory, HasUuids, BelongsToTenant;

    protected $table = 'payments_out';

    protected $fillable = [
        'tenant_id', 'bill_id', 'amount', 'payment_date',
        'payment_method', 'reference', 'notes',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
        'payment_date' => 'date',
    ];

    public function bill()
    {
        return $this->belongsTo(Bill::class);
    }
}

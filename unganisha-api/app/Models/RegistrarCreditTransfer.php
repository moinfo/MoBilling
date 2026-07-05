<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * A request to reallocate prepaid registrar credit between zones. The registry
 * (TZNIC) has no API for this, so the actual move is done registry-side; this
 * tracks the request (pending) until staff confirm it completed. It NEVER
 * changes the displayed live balance.
 */
class RegistrarCreditTransfer extends Model
{
    use HasUuids;

    protected $fillable = [
        'registrar_account_id', 'from_zone', 'to_zone', 'amount', 'status',
        'reference', 'notes', 'requested_by', 'requested_by_name', 'completed_at',
    ];

    protected $casts = [
        'amount'       => 'decimal:2',
        'completed_at' => 'datetime',
    ];

    public function requester()
    {
        return $this->belongsTo(User::class, 'requested_by');
    }
}

<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class PettyCashTransaction extends Model
{
    use HasFactory, HasUuids, SoftDeletes, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'petty_cash_account_id', 'created_by',
        'type', 'amount', 'transaction_date',
        'reconciliation_id', 'reference', 'notes',
        'given_by_name', 'received_by_name', 'voucher_attachment_path',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
        'transaction_date' => 'date',
    ];

    public function account()
    {
        return $this->belongsTo(PettyCashAccount::class, 'petty_cash_account_id');
    }

    public function reconciliation()
    {
        return $this->belongsTo(PettyCashReconciliation::class, 'reconciliation_id');
    }

    public function createdBy()
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    protected static function booted(): void
    {
        static::saving(function (self $tx) {
            $isAdjustment = in_array($tx->type, ['adjustment_in', 'adjustment_out'], true);
            $hasReconciliation = !empty($tx->reconciliation_id);
            if ($isAdjustment && !$hasReconciliation) {
                throw new \LogicException("PettyCashTransaction of type {$tx->type} must have a reconciliation_id.");
            }
            if (!$isAdjustment && $hasReconciliation) {
                throw new \LogicException("PettyCashTransaction of type {$tx->type} must not have a reconciliation_id (adjustments only).");
            }
        });
    }
}

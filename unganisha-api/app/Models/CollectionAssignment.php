<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * A per-invoice collection target + commission set manually by an admin when assigning an invoice
 * to a collector. Independent of the period-based StaffTarget system. Commission is an accrual;
 * the payout happens outside the system (paid_out_at just records that it was done).
 */
class CollectionAssignment extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'document_id', 'user_id', 'assigned_by', 'batch_id', 'target_amount',
        'commission_type', 'commission_value', 'baseline_paid', 'status', 'paid_out_at', 'paid_out_by',
    ];

    protected $casts = [
        'target_amount' => 'decimal:2',
        'commission_value' => 'decimal:2',
        'baseline_paid' => 'decimal:2',
        'paid_out_at' => 'datetime',
    ];

    public function document() { return $this->belongsTo(Document::class); }
    public function user() { return $this->belongsTo(User::class); }
    public function assigner() { return $this->belongsTo(User::class, 'assigned_by'); }

    /** Pure commission math: percentage => value% of min(collected,target); fixed => full value only once target reached. */
    public static function commissionFor(string $type, float $value, float $target, float $collected): float
    {
        $counted = min($collected, $target);

        return round(match ($type) {
            'percentage' => $counted * $value / 100,
            'fixed' => ($target > 0 && $collected >= $target) ? $value : 0.0,
            default => 0.0,
        }, 2);
    }

    /**
     * The single source of truth for progress/commission. Collected = net payments (payments - refunds)
     * on the document since assignment: max(0, currentNetPaid - baseline_paid).
     * $currentNetPaid may be passed to avoid a query when the document sums are eager-loaded.
     */
    public function progress(?float $currentNetPaid = null): array
    {
        if ($currentNetPaid === null) {
            $doc = Document::withoutGlobalScopes()->find($this->document_id);
            $currentNetPaid = $doc ? (float) $doc->paid_amount : (float) $this->baseline_paid;
        }
        $target = (float) $this->target_amount;
        $collected = max(0.0, round($currentNetPaid - (float) $this->baseline_paid, 2));
        $commission = self::commissionFor($this->commission_type, (float) $this->commission_value, $target, $collected);

        return [
            'target' => $target,
            'collected' => $collected,
            'remaining' => max(0.0, round($target - $collected, 2)),
            'commission_earned' => $commission,
            'achieved' => $target > 0 && $collected >= $target,
        ];
    }

    /** Complete/cancel active assignments of a document according to its current status. */
    public static function syncForDocument(Document $document): void
    {
        $new = match (true) {
            $document->status === 'paid' => 'completed',
            $document->status === 'cancelled' => 'cancelled',
            default => null,
        };
        if ($new) {
            static::withoutGlobalScopes()->where('document_id', $document->id)->where('status', 'active')->update(['status' => $new]);
        }
    }
}

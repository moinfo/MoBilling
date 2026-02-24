<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Facades\DB;

class TenantSubscription extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'subscription_plan_id', 'user_id',
        'status', 'starts_at', 'ends_at', 'amount_paid',
        'order_tracking_id', 'pesapal_redirect_url',
        'payment_status_description', 'confirmation_code',
        'payment_method_used', 'gateway_response', 'paid_at',
        'invoice_number', 'payment_method', 'payment_reference',
        'payment_confirmed_at', 'payment_confirmed_by',
        'invoice_due_date', 'payment_proof_path',
    ];

    protected $casts = [
        'amount_paid' => 'decimal:2',
        'starts_at' => 'datetime',
        'ends_at' => 'datetime',
        'paid_at' => 'datetime',
        'gateway_response' => 'array',
        'payment_confirmed_at' => 'datetime',
        'invoice_due_date' => 'date',
    ];

    public function plan(): BelongsTo
    {
        return $this->belongsTo(SubscriptionPlan::class, 'subscription_plan_id');
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function confirmedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'payment_confirmed_by');
    }

    public function isActive(): bool
    {
        return $this->status === 'active' && $this->ends_at && $this->ends_at->isFuture();
    }

    public function isPaid(): bool
    {
        return $this->paid_at !== null || $this->payment_confirmed_at !== null;
    }

    public function isOverdue(): bool
    {
        return !$this->isPaid()
            && $this->status === 'pending'
            && $this->invoice_due_date
            && $this->invoice_due_date->isPast();
    }

    public static function generateInvoiceNumber(): string
    {
        $year = now()->year;
        $prefix = "MOBI-{$year}-";

        $last = static::withoutGlobalScopes()
            ->where('invoice_number', 'like', "{$prefix}%")
            ->orderByDesc('invoice_number')
            ->value('invoice_number');

        $nextSeq = 1;
        if ($last) {
            $lastSeq = (int) str_replace($prefix, '', $last);
            $nextSeq = $lastSeq + 1;
        }

        return $prefix . str_pad($nextSeq, 5, '0', STR_PAD_LEFT);
    }
}

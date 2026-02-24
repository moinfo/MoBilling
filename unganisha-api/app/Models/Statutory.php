<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Statutory extends Model
{
    use HasFactory, HasUuids, SoftDeletes, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'name', 'bill_category_id', 'amount',
        'cycle', 'issue_date', 'next_due_date', 'remind_days_before',
        'is_active', 'notes',
    ];

    protected $casts = [
        'issue_date' => 'date',
        'next_due_date' => 'date',
        'amount' => 'decimal:2',
        'is_active' => 'boolean',
        'remind_days_before' => 'integer',
    ];

    /**
     * Compute next_due_date from issue_date + cycle.
     */
    public static function computeDueDate(\Carbon\Carbon $issueDate, string $cycle): \Carbon\Carbon
    {
        return match ($cycle) {
            'once' => $issueDate->copy(),
            'monthly' => $issueDate->copy()->addMonth(),
            'quarterly' => $issueDate->copy()->addMonths(3),
            'half_yearly' => $issueDate->copy()->addMonths(6),
            'yearly' => $issueDate->copy()->addYear(),
        };
    }

    public function tenant()
    {
        return $this->belongsTo(Tenant::class);
    }

    public function billCategory()
    {
        return $this->belongsTo(BillCategory::class, 'bill_category_id');
    }

    public function bills()
    {
        return $this->hasMany(Bill::class, 'statutory_id');
    }

    public function currentBill()
    {
        return $this->hasOne(Bill::class, 'statutory_id')
            ->whereNull('paid_at')
            ->latest('due_date');
    }

    /**
     * Advance next_due_date by one cycle period.
     * Returns false for "once" obligations (no next period).
     */
    public function advanceDueDate(): bool
    {
        if ($this->cycle === 'once') {
            $this->update(['is_active' => false]);
            return false;
        }

        $this->next_due_date = match ($this->cycle) {
            'monthly' => $this->next_due_date->addMonth(),
            'quarterly' => $this->next_due_date->addMonths(3),
            'half_yearly' => $this->next_due_date->addMonths(6),
            'yearly' => $this->next_due_date->addYear(),
        };
        $this->save();
        return true;
    }

    /**
     * Generate a bill for the current period.
     */
    public function generateBill(): Bill
    {
        return Bill::create([
            'tenant_id' => $this->tenant_id,
            'statutory_id' => $this->id,
            'name' => $this->name,
            'bill_category_id' => $this->bill_category_id,
            'amount' => $this->amount,
            'cycle' => $this->cycle,
            'due_date' => $this->next_due_date,
            'issue_date' => now()->toDateString(),
            'remind_days_before' => $this->remind_days_before,
            'is_active' => true,
        ]);
    }
}

<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Bill extends Model
{
    use HasFactory, HasUuids, SoftDeletes, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'statutory_id', 'name', 'category', 'bill_category_id',
        'issue_date', 'amount', 'cycle', 'due_date',
        'remind_days_before', 'is_active', 'paid_at', 'notes',
    ];

    protected $casts = [
        'due_date' => 'date',
        'issue_date' => 'date',
        'amount' => 'decimal:2',
        'is_active' => 'boolean',
        'paid_at' => 'datetime',
    ];

    public function statutory()
    {
        return $this->belongsTo(Statutory::class);
    }

    public function billCategory()
    {
        return $this->belongsTo(BillCategory::class, 'bill_category_id');
    }

    public function payments()
    {
        return $this->hasMany(PaymentOut::class);
    }

    public function getNextDueDateAttribute()
    {
        return match ($this->cycle) {
            'once' => null,
            'monthly' => $this->due_date->addMonth(),
            'quarterly' => $this->due_date->addMonths(3),
            'half_yearly' => $this->due_date->addMonths(6),
            'yearly' => $this->due_date->addYear(),
        };
    }
}

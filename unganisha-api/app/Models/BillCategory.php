<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class BillCategory extends Model
{
    use HasFactory, HasUuids, SoftDeletes, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'parent_id', 'name', 'billing_cycle', 'is_active',
    ];

    protected $casts = [
        'is_active' => 'boolean',
    ];

    public function parent()
    {
        return $this->belongsTo(BillCategory::class, 'parent_id');
    }

    public function children()
    {
        return $this->hasMany(BillCategory::class, 'parent_id');
    }

    public function bills()
    {
        return $this->hasMany(Bill::class, 'bill_category_id');
    }

    public function scopeTopLevel($query)
    {
        return $query->whereNull('parent_id');
    }
}

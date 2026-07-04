<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class ProductAddon extends Model
{
    use HasFactory, HasUuids, SoftDeletes, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'name', 'description', 'price',
        'billing_cycle', 'tax_percent', 'is_active',
    ];

    protected $casts = [
        'price' => 'decimal:2',
        'tax_percent' => 'decimal:2',
        'is_active' => 'boolean',
    ];

    public function products()
    {
        return $this->belongsToMany(
            ProductService::class,
            'product_addon_links',
            'product_addon_id',
            'product_service_id'
        );
    }

    public function scopeActive($query)
    {
        return $query->where('is_active', true);
    }
}

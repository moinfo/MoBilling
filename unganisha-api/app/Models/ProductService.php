<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class ProductService extends Model
{
    use HasFactory, HasUuids, SoftDeletes, BelongsToTenant;

    protected $table = 'product_services';

    protected $fillable = [
        'tenant_id', 'type', 'name', 'code', 'description',
        'price', 'tax_percent', 'unit', 'category', 'billing_cycle', 'is_active', 'legacy_id',
        'provisioning_type', 'server_id', 'cpanel_package', 'auto_provision', 'portal_visible',
    ];

    protected $casts = [
        'auto_provision' => 'boolean',
        'price' => 'decimal:2',
        'tax_percent' => 'decimal:2',
        'is_active' => 'boolean',
    ];

    public function server()
    {
        return $this->belongsTo(Server::class);
    }

    public function scopeProducts($query)
    {
        return $query->where('type', 'product');
    }

    public function scopeServices($query)
    {
        return $query->where('type', 'service');
    }

    public function scopeActive($query)
    {
        return $query->where('is_active', true);
    }
}

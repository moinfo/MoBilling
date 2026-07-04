<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class ConfigOptionGroup extends Model
{
    use HasFactory, HasUuids, SoftDeletes, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'name', 'description', 'is_active',
    ];

    protected $casts = [
        'is_active' => 'boolean',
    ];

    public function options()
    {
        return $this->hasMany(ConfigOption::class)->orderBy('sort_order')->orderBy('name');
    }

    public function products()
    {
        return $this->belongsToMany(
            ProductService::class,
            'product_config_group_links',
            'config_option_group_id',
            'product_service_id'
        );
    }

    public function scopeActive($query)
    {
        return $query->where('is_active', true);
    }
}

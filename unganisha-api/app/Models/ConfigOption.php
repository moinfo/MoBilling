<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class ConfigOption extends Model
{
    use HasFactory, HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'config_option_group_id', 'name',
        'option_type', 'unit_price', 'sort_order',
    ];

    protected $casts = [
        'unit_price' => 'decimal:2',
        'sort_order' => 'integer',
    ];

    public function group()
    {
        return $this->belongsTo(ConfigOptionGroup::class, 'config_option_group_id');
    }

    public function choices()
    {
        return $this->hasMany(ConfigOptionChoice::class)->orderBy('sort_order');
    }
}

<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class ServedTarget extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'new_customers_target', 'called_customers_target',
        'active_days', 'effective_from',
    ];

    protected $casts = [
        'active_days'            => 'array',
        'effective_from'         => 'date',
        'new_customers_target'   => 'integer',
        'called_customers_target'=> 'integer',
    ];
}

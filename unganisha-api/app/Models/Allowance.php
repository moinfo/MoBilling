<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Allowance extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = ['tenant_id', 'name', 'calculation_type', 'default_amount', 'is_active'];

    protected $casts = [
        'is_active' => 'boolean',
    ];

    public function subscriptions(): HasMany
    {
        return $this->hasMany(AllowanceSubscription::class);
    }
}

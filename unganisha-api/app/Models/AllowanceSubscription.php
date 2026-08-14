<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AllowanceSubscription extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = ['tenant_id', 'user_id', 'allowance_id', 'amount_override', 'is_active'];

    protected $casts = [
        'is_active' => 'boolean',
    ];

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function allowance(): BelongsTo
    {
        return $this->belongsTo(Allowance::class);
    }
}

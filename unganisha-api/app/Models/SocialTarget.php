<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class SocialTarget extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'user_id', 'metric', 'weekly_target', 'daily_target', 'active_days', 'effective_from',
    ];

    protected $casts = [
        'active_days'    => 'array',
        'effective_from' => 'date',
        'weekly_target'  => 'integer',
        'daily_target'   => 'integer',
    ];

    public function user()
    {
        return $this->belongsTo(User::class);
    }
}

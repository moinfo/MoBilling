<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class SocialTarget extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'image_target', 'video_target', 'active_days', 'effective_from',
    ];

    protected $casts = [
        'active_days'    => 'array',
        'effective_from' => 'date',
        'image_target'   => 'integer',
        'video_target'   => 'integer',
    ];
}

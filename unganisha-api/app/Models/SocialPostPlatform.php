<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class SocialPostPlatform extends Model
{
    use HasUuids;

    protected $fillable = ['social_post_id', 'platform', 'posted', 'posted_at', 'post_url', 'posted_by'];

    protected $casts = [
        'posted'    => 'boolean',
        'posted_at' => 'datetime',
    ];

    public function post()
    {
        return $this->belongsTo(SocialPost::class, 'social_post_id');
    }
}

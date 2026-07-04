<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class KbArticle extends Model
{
    use HasUuids, BelongsToTenant, SoftDeletes;

    protected $fillable = [
        'tenant_id', 'kb_category_id', 'title', 'slug', 'body',
        'is_published', 'views', 'sort_order',
    ];

    protected $casts = [
        'is_published' => 'boolean',
        'views'        => 'integer',
        'sort_order'   => 'integer',
    ];

    public function category()
    {
        return $this->belongsTo(KbCategory::class, 'kb_category_id');
    }

    public function scopePublished($query)
    {
        return $query->where('is_published', true);
    }
}

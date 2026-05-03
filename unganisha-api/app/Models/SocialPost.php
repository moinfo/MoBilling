<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class SocialPost extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'title', 'type', 'scheduled_date', 'brief', 'caption',
        'design_file_url', 'design_notes',
        'assigned_designer_id', 'assigned_creator_id',
        'design_status', 'content_status', 'status', 'created_by',
    ];

    protected $casts = [
        'scheduled_date' => 'date',
    ];

    public function platforms()
    {
        return $this->hasMany(SocialPostPlatform::class);
    }

    public function designer()
    {
        return $this->belongsTo(User::class, 'assigned_designer_id');
    }

    public function creator()
    {
        return $this->belongsTo(User::class, 'assigned_creator_id');
    }

    // Recompute overall status from platform postings
    public function syncStatus(): void
    {
        $platforms = $this->platforms;
        $total  = $platforms->count();
        $posted = $platforms->where('posted', true)->count();

        $status = match (true) {
            $total > 0 && $posted === $total => 'posted',
            $posted > 0                      => 'partial_posted',
            $this->content_status === 'ready' => 'content_ready',
            $this->design_status === 'done'   => 'designing',
            default                           => 'planned',
        };

        $this->updateQuietly(['status' => $status]);
    }
}

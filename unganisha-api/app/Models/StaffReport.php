<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class StaffReport extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'user_id', 'report_type', 'period_date',
        'achievements', 'challenges', 'plans', 'notes',
        'status', 'is_late', 'reviewed_by', 'reviewed_at', 'review_notes', 'rating',
    ];

    protected $casts = [
        'period_date' => 'date',
        'reviewed_at' => 'datetime',
        'rating'      => 'integer',
        'is_late'     => 'boolean',
    ];

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function reviewer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'reviewed_by');
    }

    public function replies()
    {
        return $this->hasMany(StaffReportReply::class)->with('user:id,name')->orderBy('created_at');
    }
}

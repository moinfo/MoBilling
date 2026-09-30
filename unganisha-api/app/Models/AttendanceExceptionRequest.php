<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AttendanceExceptionRequest extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'user_id', 'date', 'type', 'comment',
        'status', 'reviewed_by', 'reviewed_at', 'review_note',
    ];

    protected $casts = [
        'date' => 'date',
        'reviewed_at' => 'datetime',
    ];

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function reviewer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'reviewed_by');
    }
}

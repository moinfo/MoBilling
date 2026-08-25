<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class Broadcast extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id',
        'sent_by',
        'client_ids',
        'total_recipients',
        'channel',
        'subject',
        'body',
        'sms_body',
        'whatsapp_body',
        'sent_count',
        'failed_count',
        'sent_client_ids',
        'failed_client_ids',
        'retry_of_broadcast_id',
    ];

    protected $casts = [
        'client_ids' => 'array',
        'sent_client_ids' => 'array',
        'failed_client_ids' => 'array',
    ];

    protected $appends = ['in_progress'];

    /** Still being processed in the background — sent_count/failed_count aren't final yet. */
    public function getInProgressAttribute(): bool
    {
        return ($this->sent_count + $this->failed_count) < $this->total_recipients;
    }

    public function sender()
    {
        return $this->belongsTo(User::class, 'sent_by');
    }

    public function retryOf()
    {
        return $this->belongsTo(self::class, 'retry_of_broadcast_id');
    }
}

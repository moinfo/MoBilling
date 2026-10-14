<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Storage;

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
        'whatsapp_image_path',
        'sent_count',
        'failed_count',
        'sent_client_ids',
        'failed_client_ids',
        'failure_reasons',
        'retry_of_broadcast_id',
    ];

    protected $casts = [
        'client_ids' => 'array',
        'sent_client_ids' => 'array',
        'failed_client_ids' => 'array',
        'failure_reasons' => 'array',
    ];

    protected $appends = ['in_progress', 'whatsapp_image_url'];

    /** Still being processed in the background — sent_count/failed_count aren't final yet. */
    public function getInProgressAttribute(): bool
    {
        return ($this->sent_count + $this->failed_count) < $this->total_recipients;
    }

    /** Public URL Meta's Graph API can fetch as the WhatsApp template's header image. */
    public function getWhatsappImageUrlAttribute(): ?string
    {
        return $this->whatsapp_image_path ? Storage::disk('public')->url($this->whatsapp_image_path) : null;
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

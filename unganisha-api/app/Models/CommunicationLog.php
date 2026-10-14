<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class CommunicationLog extends Model
{
    use HasUuids, BelongsToTenant;

    const CREATED_AT = 'created_at';
    const UPDATED_AT = 'updated_at';

    protected $fillable = [
        'tenant_id', 'client_id', 'channel', 'type',
        'recipient', 'subject', 'message', 'status',
        'error', 'metadata',
        'mosms_message_id', 'client_ref', 'delivery_status', 'delivered_at', 'delivery_error',
    ];

    protected $casts = [
        'metadata' => 'array',
        'created_at' => 'datetime',
        'delivered_at' => 'datetime',
    ];

    public function client()
    {
        return $this->belongsTo(Client::class);
    }
}

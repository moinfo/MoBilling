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
        'sent_count',
        'failed_count',
    ];

    protected $casts = [
        'client_ids' => 'array',
    ];

    public function sender()
    {
        return $this->belongsTo(User::class, 'sent_by');
    }
}

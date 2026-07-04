<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class TicketAttachment extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'ticket_reply_id', 'path', 'original_name', 'mime', 'size',
    ];

    protected $casts = [
        'size' => 'integer',
    ];

    public function reply()
    {
        return $this->belongsTo(TicketReply::class, 'ticket_reply_id');
    }
}

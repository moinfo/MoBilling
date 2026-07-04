<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class TicketReply extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'ticket_id', 'author_type', 'user_id', 'client_user_id', 'message',
    ];

    public function ticket()
    {
        return $this->belongsTo(Ticket::class);
    }

    public function attachments()
    {
        return $this->hasMany(TicketAttachment::class);
    }

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function clientUser()
    {
        return $this->belongsTo(ClientUser::class);
    }

    /** Display name regardless of author side. */
    public function authorName(): string
    {
        return $this->author_type === 'staff'
            ? ($this->user?->name ?? 'Support')
            : ($this->clientUser?->name ?? $this->ticket?->client?->name ?? 'Client');
    }
}

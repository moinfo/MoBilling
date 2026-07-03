<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class Ticket extends Model
{
    use HasUuids, BelongsToTenant;

    public const STATUSES = ['open', 'answered', 'customer_reply', 'closed'];
    public const PRIORITIES = ['low', 'medium', 'high'];

    protected $fillable = [
        'tenant_id', 'client_id', 'ticket_number', 'subject', 'status',
        'priority', 'opened_by', 'assigned_to', 'last_reply_at',
    ];

    protected $casts = [
        'last_reply_at' => 'datetime',
    ];

    public function client()
    {
        return $this->belongsTo(Client::class);
    }

    public function replies()
    {
        return $this->hasMany(TicketReply::class)->orderBy('created_at');
    }

    public function openedBy()
    {
        return $this->belongsTo(ClientUser::class, 'opened_by');
    }

    public function assignee()
    {
        return $this->belongsTo(User::class, 'assigned_to');
    }

    /** Per-tenant sequential number: TKT-0001. */
    public static function nextNumber(string $tenantId): string
    {
        $last = static::withoutGlobalScopes()
            ->where('tenant_id', $tenantId)
            ->orderByDesc('created_at')
            ->value('ticket_number');

        $n = $last && preg_match('/(\d+)$/', $last, $m) ? ((int) $m[1]) + 1 : 1;

        return 'TKT-' . str_pad((string) $n, 4, '0', STR_PAD_LEFT);
    }
}

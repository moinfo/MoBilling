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
    public const DEPARTMENTS = ['support', 'billing', 'sales'];

    protected $fillable = [
        'tenant_id', 'client_id', 'ticket_number', 'subject', 'department',
        'related_service', 'status', 'priority', 'opened_by', 'assigned_to', 'last_reply_at',
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

    /**
     * Per-tenant sequential number: TKT-0001. Takes the highest numeric suffix (not the newest
     * created_at — two tickets in the same second made that ambiguous and repeated a number).
     */
    public static function nextNumber(string $tenantId): string
    {
        $max = (int) static::withoutGlobalScopes()
            ->where('tenant_id', $tenantId)
            ->whereRaw("ticket_number REGEXP '^TKT-[0-9]+$'")
            ->max(\Illuminate\Support\Facades\DB::raw("CAST(SUBSTRING(ticket_number, 5) AS UNSIGNED)"));

        return 'TKT-' . str_pad((string) ($max + 1), 4, '0', STR_PAD_LEFT);
    }

    /**
     * Create a ticket with the next number, retrying if a concurrent request took the same
     * number first (the (tenant_id, ticket_number) unique key turns that race into an
     * exception instead of a duplicate). Pass tenant_id in $attributes; ticket_number is set here.
     */
    public static function createNumbered(array $attributes): static
    {
        for ($attempt = 1; ; $attempt++) {
            $attributes['ticket_number'] = static::nextNumber($attributes['tenant_id']);
            try {
                return static::create($attributes);
            } catch (\Illuminate\Database\UniqueConstraintViolationException $e) {
                if ($attempt >= 5) {
                    throw $e;
                }
                usleep(random_int(20000, 80000));
            }
        }
    }
}

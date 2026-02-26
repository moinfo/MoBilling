<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Followup extends Model
{
    use HasFactory, HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'document_id', 'client_id', 'user_id',
        'call_date', 'outcome', 'notes', 'promise_date', 'promise_amount',
        'next_followup', 'status',
    ];

    protected $casts = [
        'call_date' => 'datetime',
        'promise_date' => 'date',
        'next_followup' => 'date',
        'promise_amount' => 'decimal:2',
    ];

    public function document()
    {
        return $this->belongsTo(Document::class);
    }

    public function client()
    {
        return $this->belongsTo(Client::class);
    }

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function scopeDueToday($query)
    {
        return $query->whereDate('next_followup', today())
            ->whereIn('status', ['pending', 'open', 'broken']);
    }

    public function scopeOverdue($query)
    {
        return $query->whereDate('next_followup', '<', today())
            ->whereIn('status', ['pending', 'open', 'broken']);
    }

    public function scopeActive($query)
    {
        return $query->whereIn('status', ['pending', 'open', 'broken']);
    }
}

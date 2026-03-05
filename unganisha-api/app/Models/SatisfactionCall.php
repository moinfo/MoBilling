<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class SatisfactionCall extends Model
{
    use HasFactory, HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'client_id', 'user_id',
        'scheduled_date', 'called_at', 'outcome', 'rating',
        'feedback', 'internal_notes', 'status', 'month_key',
    ];

    protected $casts = [
        'scheduled_date' => 'date',
        'called_at' => 'datetime',
        'rating' => 'integer',
    ];

    public function client()
    {
        return $this->belongsTo(Client::class);
    }

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function scopeScheduledToday($query)
    {
        return $query->whereDate('scheduled_date', today())
            ->where('status', 'scheduled');
    }

    public function scopeOverdue($query)
    {
        return $query->whereDate('scheduled_date', '<', today())
            ->where('status', 'scheduled');
    }

    public function scopeForMonth($query, string $monthKey)
    {
        return $query->where('month_key', $monthKey);
    }
}

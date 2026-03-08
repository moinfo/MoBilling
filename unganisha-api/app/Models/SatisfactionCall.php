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
        'follow_up_of',
        'appointment_requested', 'appointment_date', 'appointment_notes', 'appointment_status',
    ];

    protected $casts = [
        'scheduled_date' => 'date',
        'called_at' => 'datetime',
        'rating' => 'integer',
        'appointment_requested' => 'boolean',
        'appointment_date' => 'date',
    ];

    public function client()
    {
        return $this->belongsTo(Client::class);
    }

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function originalCall()
    {
        return $this->belongsTo(self::class, 'follow_up_of');
    }

    public function followUp()
    {
        return $this->hasOne(self::class, 'follow_up_of');
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

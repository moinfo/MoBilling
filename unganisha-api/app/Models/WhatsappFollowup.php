<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use App\Traits\BelongsToTenant;

class WhatsappFollowup extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id',
        'whatsapp_contact_id',
        'user_id',
        'call_date',
        'outcome',
        'notes',
        'next_followup_date',
    ];

    protected $casts = [
        'call_date'          => 'date',
        'next_followup_date' => 'date',
    ];

    public function contact()
    {
        return $this->belongsTo(WhatsappContact::class, 'whatsapp_contact_id');
    }

    public function user()
    {
        return $this->belongsTo(User::class);
    }
}

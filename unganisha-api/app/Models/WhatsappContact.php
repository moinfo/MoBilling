<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use App\Traits\BelongsToTenant;

class WhatsappContact extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id',
        'name',
        'phone',
        'label',
        'is_important',
        'source',
        'campaign_id',
        'notes',
        'next_followup_date',
        'assigned_to',
        'client_id',
        'services',
    ];

    protected $casts = [
        'is_important'       => 'boolean',
        'next_followup_date' => 'date',
        'services'           => 'array',
    ];

    public function followups()
    {
        return $this->hasMany(WhatsappFollowup::class, 'whatsapp_contact_id')->latest('call_date');
    }

    public function campaign()
    {
        return $this->belongsTo(WhatsappCampaign::class, 'campaign_id');
    }

    public function client()
    {
        return $this->belongsTo(Client::class);
    }

    public function assignedUser()
    {
        return $this->belongsTo(User::class, 'assigned_to');
    }
}

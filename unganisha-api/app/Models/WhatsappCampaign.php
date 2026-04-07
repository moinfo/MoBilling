<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use App\Traits\BelongsToTenant;

class WhatsappCampaign extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id',
        'name',
        'start_date',
        'end_date',
        'budget',
        'notes',
    ];

    protected $casts = [
        'start_date' => 'date',
        'end_date'   => 'date',
        'budget'     => 'float',
    ];

    public function contacts()
    {
        return $this->hasMany(WhatsappContact::class, 'campaign_id');
    }
}

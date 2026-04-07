<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use App\Traits\BelongsToTenant;

class FieldVisit extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'session_id', 'officer_id',
        'business_name', 'location', 'phone',
        'services', 'feedback', 'status', 'client_id',
        'next_followup_date',
    ];

    protected $casts = [
        'services'           => 'array',
        'next_followup_date' => 'date',
    ];

    public function session()   { return $this->belongsTo(FieldSession::class, 'session_id'); }
    public function officer()   { return $this->belongsTo(User::class, 'officer_id'); }
    public function client()    { return $this->belongsTo(Client::class); }
    public function followups() { return $this->hasMany(FieldFollowup::class, 'visit_id'); }
}

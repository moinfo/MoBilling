<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use App\Traits\BelongsToTenant;

class FieldFollowup extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'visit_id', 'user_id',
        'call_date', 'outcome', 'notes', 'next_followup_date',
    ];

    protected $casts = [
        'call_date'          => 'date',
        'next_followup_date' => 'date',
    ];

    public function visit() { return $this->belongsTo(FieldVisit::class, 'visit_id'); }
    public function user()  { return $this->belongsTo(User::class); }
}

<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use App\Traits\BelongsToTenant;

class FieldSession extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'officer_id', 'visit_date',
        'area', 'summary', 'challenges', 'recommendations',
    ];

    protected $casts = ['visit_date' => 'date'];

    public function officer() { return $this->belongsTo(User::class, 'officer_id'); }
    public function visits()  { return $this->hasMany(FieldVisit::class, 'session_id'); }
}

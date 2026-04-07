<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use App\Traits\BelongsToTenant;

class FieldTarget extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'officer_id', 'month', 'year', 'target_clients',
    ];

    protected $casts = ['month' => 'integer', 'year' => 'integer', 'target_clients' => 'integer'];

    public function officer() { return $this->belongsTo(User::class, 'officer_id'); }
}

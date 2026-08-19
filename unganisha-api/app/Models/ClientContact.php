<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class ClientContact extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'client_id', 'name', 'email', 'phone', 'role', 'notes',
    ];

    public function client()
    {
        return $this->belongsTo(Client::class);
    }
}

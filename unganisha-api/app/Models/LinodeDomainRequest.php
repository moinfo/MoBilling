<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class LinodeDomainRequest extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'client_id', 'linode_resource_id', 'domain', 'status', 'requested_by', 'decided_by', 'decided_at', 'note',
    ];

    protected $casts = ['decided_at' => 'datetime'];

    public function client()
    {
        return $this->belongsTo(Client::class);
    }

    public function server()
    {
        return $this->belongsTo(LinodeResource::class, 'linode_resource_id');
    }
}

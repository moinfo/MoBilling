<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class ProvisioningLog extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'hosting_account_id', 'server_id',
        'action', 'request', 'response', 'status', 'error',
    ];

    protected $casts = [
        'request'  => 'array',
        'response' => 'array',
    ];

    public function hostingAccount()
    {
        return $this->belongsTo(HostingAccount::class);
    }
}

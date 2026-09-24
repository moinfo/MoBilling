<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class LinodeAuditLog extends Model
{
    use HasUuids, BelongsToTenant;

    public const UPDATED_AT = null;

    protected $fillable = ['tenant_id', 'user_id', 'linode_account_id', 'action', 'target', 'request', 'response_status', 'error'];

    protected $casts = ['request' => 'array'];
}

<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * A message drained from the FRED registry poll queue (transfers away, pending
 * deletions, expiry/low-credit warnings, technical-check results). Platform-
 * level (the poll queue belongs to the registrar account, not a tenant).
 */
class DomainRegistryEvent extends Model
{
    use HasUuids;

    protected $fillable = [
        'tenant_id', 'registry_msg_id', 'msg_type', 'msg_date',
        'domain', 'text', 'data', 'acked', 'acted',
    ];

    protected $casts = [
        'data'     => 'array',
        'msg_date' => 'datetime',
        'acked'    => 'boolean',
        'acted'    => 'boolean',
    ];
}

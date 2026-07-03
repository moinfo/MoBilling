<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * TLD pricing. tenant_id NULL = platform base cost; a tenant row overrides
 * with that tenant's retail price. NOT BelongsToTenant (see RegistrarAccount).
 */
class DomainTld extends Model
{
    use HasUuids;

    protected $fillable = [
        'tenant_id', 'tld', 'register_price', 'renew_price', 'transfer_price',
        'years_min', 'years_max', 'is_active',
    ];

    protected $casts = [
        'register_price' => 'decimal:2',
        'renew_price'    => 'decimal:2',
        'transfer_price' => 'decimal:2',
        'is_active'      => 'boolean',
    ];

    /** Retail price row for a tenant+tld, falling back to the platform row. */
    public static function priceFor(string $tenantId, string $tld): ?self
    {
        return static::where('tld', $tld)->where('is_active', true)
            ->where(fn ($q) => $q->where('tenant_id', $tenantId)->orWhereNull('tenant_id'))
            ->orderByRaw('tenant_id IS NULL') // tenant row first
            ->first();
    }
}

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
        'tenant_id', 'tld', 'register_price', 'renew_price', 'transfer_price', 'reseller_price',
        'years_min', 'years_max', 'is_active', 'is_unmanaged',
        'is_popular', 'sort_order', 'registrar', 'usd_register', 'usd_renew', 'usd_transfer', 'price_overridden', 'overridden_ops', 'usd_changed', 'usd_prev', 'usd_synced_at',
    ];

    /** Wholesale USD cost must never leave the staff-only Name.com endpoints. */
    protected $hidden = ['usd_register', 'usd_renew', 'usd_transfer', 'usd_prev', 'usd_changed', 'usd_synced_at', 'price_overridden', 'overridden_ops'];

    protected $casts = [
        'register_price' => 'decimal:2',
        'renew_price'    => 'decimal:2',
        'transfer_price' => 'decimal:2',
        'reseller_price' => 'decimal:2',
        'is_active'      => 'boolean',
        'is_unmanaged'   => 'boolean',
        'is_popular'     => 'boolean',
        'sort_order'     => 'integer',
        'usd_register'   => 'float',
        'usd_renew'      => 'float',
        'usd_transfer'   => 'float',
        'price_overridden' => 'boolean',
        'usd_changed'    => 'boolean',
        'usd_prev'       => 'array',
        'overridden_ops' => 'array',
        'usd_synced_at'  => 'datetime',
    ];

    public function isNameCom(): bool
    {
        return $this->registrar === 'namecom';
    }

    /**
     * Retail price row for a tenant+tld, falling back to the platform row.
     * A tenant's own Name.com row is authoritative for its TLD: when it exists but is not on
     * sale the TLD is NOT sold (no fallback to a platform placeholder).
     */
    public static function priceFor(string $tenantId, string $tld): ?self
    {
        $own = static::where('tenant_id', $tenantId)->where('tld', $tld)->where('registrar', 'namecom')->first();
        if ($own) return $own->is_active ? $own : null;

        return static::where('tld', $tld)->where('is_active', true)
            ->where(fn ($q) => $q->where('tenant_id', $tenantId)->orWhereNull('tenant_id'))
            ->orderByRaw('tenant_id IS NULL') // tenant row first
            ->first();
    }

    /** The tenant's Name.com row for a TLD that exists but is not on sale (staff hint), else null. */
    public static function disabledNameCom(string $tenantId, string $tld): ?self
    {
        return static::where('tenant_id', $tenantId)->where('tld', $tld)->where('registrar', 'namecom')->where('is_active', false)->first();
    }

    public const DISABLED_HINT = 'Enable .%s in Settings > Domains > Name.com > TLDs & pricing to sell it.';

    /**
     * Every TLD currently on sale for the tenant (tenant rows win over platform rows), keyed by tld,
     * popular first. A tenant Name.com row that is not on sale hides a platform placeholder of the same TLD.
     * @return \Illuminate\Support\Collection<string, self>
     */
    public static function onSaleCatalog(string $tenantId)
    {
        $shadow = static::where('tenant_id', $tenantId)->where('registrar', 'namecom')->where('is_active', false)->pluck('tld')->all();

        return static::where('is_active', true)
            ->where(fn ($q) => $q->where('tenant_id', $tenantId)->orWhereNull('tenant_id'))
            ->when($shadow, fn ($q) => $q->whereNotIn('tld', $shadow))
            ->orderByRaw('tenant_id IS NULL')
            ->get()
            ->unique('tld')
            ->sortBy([['is_popular', 'desc'], ['sort_order', 'asc'], ['tld', 'asc']])
            ->keyBy('tld');
    }
}

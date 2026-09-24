<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/** Per-tenant Name.com pricing rule and auto-register safeguards. */
class NameComSettings extends Model
{
    use HasUuids, BelongsToTenant;

    protected $table = 'namecom_settings';

    protected $fillable = ['tenant_id', 'usd_rate', 'fixed_markup', 'auto_register', 'auto_cap_usd', 'auto_daily_limit'];

    protected $casts = [
        'usd_rate'         => 'float',
        'fixed_markup'     => 'float',
        'auto_register'    => 'boolean',
        'auto_cap_usd'     => 'float',
        'auto_daily_limit' => 'integer',
    ];

    public const DEFAULTS = ['usd_rate' => 3000.0, 'fixed_markup' => 10000.0, 'auto_register' => false, 'auto_cap_usd' => 50.0, 'auto_daily_limit' => 10];

    /** Stored row or an unsaved defaults instance (owner's defaults: 3000 x USD + 10,000). */
    public static function forTenant(string $tenantId): self
    {
        $row = static::withoutGlobalScopes()->where('tenant_id', $tenantId)->first();
        if ($row) return $row;
        $new = new static(self::DEFAULTS);
        $new->tenant_id = $tenantId;
        return $new;
    }
}

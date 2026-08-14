<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * One row per tenant (firstOrCreate — see ::forTenant()), holding just the
 * PAYE bracket table now — NSSF/WCF/SDL (and anything else, e.g. NHIF)
 * live in the tenant-configurable `statutory_rates` catalog instead, since
 * PAYE is the one statutory item that's bracket-based rather than a flat
 * percentage, and every tenant has exactly one PAYE schedule (not a list
 * you'd add more of). `DEFAULT_PAYE_BRACKETS` below is a commonly-cited
 * bracket structure, NOT guaranteed to be the currently correct TRA
 * schedule — verify with TRA/an accountant before relying on this for a
 * real payroll run.
 */
class PayrollSettings extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = ['tenant_id', 'paye_brackets'];

    protected $casts = [
        'paye_brackets' => 'array',
    ];

    /** Each bracket: tax = base_deduction + rate% * (taxable_income - min), for min <= income < max (max null = no cap). */
    public const DEFAULT_PAYE_BRACKETS = [
        ['min' => 0,       'max' => 270000,  'rate' => 0,  'base_deduction' => 0],
        ['min' => 270000,  'max' => 520000,  'rate' => 8,  'base_deduction' => 0],
        ['min' => 520000,  'max' => 760000,  'rate' => 20, 'base_deduction' => 20000],
        ['min' => 760000,  'max' => 1000000, 'rate' => 25, 'base_deduction' => 68000],
        ['min' => 1000000, 'max' => null,    'rate' => 30, 'base_deduction' => 128000],
    ];

    public static function forTenant(string $tenantId): self
    {
        return static::withoutGlobalScopes()->firstOrCreate(
            ['tenant_id' => $tenantId],
            ['paye_brackets' => self::DEFAULT_PAYE_BRACKETS],
        );
    }
}

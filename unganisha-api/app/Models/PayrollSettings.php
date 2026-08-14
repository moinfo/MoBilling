<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * One row per tenant (firstOrCreate — see ::forTenant()). Every rate here
 * is tenant-editable via Settings. `DEFAULT_PAYE_BRACKETS` below is a
 * commonly-cited bracket structure, NOT guaranteed to be the currently
 * correct TRA schedule — Tanzania's PAYE brackets, NSSF/WCF/SDL
 * percentages change with the annual Finance Act. Seeded only as a
 * starting point; verify with TRA/an accountant before relying on this
 * for a real payroll run.
 */
class PayrollSettings extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'paye_brackets', 'nssf_employee_percent',
        'nssf_employer_percent', 'wcf_percent', 'sdl_percent',
    ];

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
            [
                'paye_brackets' => self::DEFAULT_PAYE_BRACKETS,
                'nssf_employee_percent' => 10.00,
                'nssf_employer_percent' => 10.00,
                'wcf_percent' => 0.50,
                'sdl_percent' => 3.50,
            ],
        );
    }
}

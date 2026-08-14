<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * A frozen snapshot — see PayrollCalculationService for how these fields
 * are computed. nssf_employer_amount/wcf_amount/sdl_amount are EMPLOYER
 * costs (informational), never subtracted from net_pay.
 */
class Payslip extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'payroll_run_id', 'user_id',
        'basic_salary', 'allowances_total', 'allowances_breakdown', 'gross_pay',
        'nssf_employee_amount', 'taxable_income', 'paye_amount',
        'other_deductions_total', 'deductions_breakdown', 'net_pay',
        'nssf_employer_amount', 'wcf_amount', 'sdl_amount', 'employer_cost_total',
    ];

    protected $casts = [
        'allowances_breakdown' => 'array',
        'deductions_breakdown' => 'array',
    ];

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function payrollRun(): BelongsTo
    {
        return $this->belongsTo(PayrollRun::class);
    }
}

<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * A frozen snapshot — see PayrollCalculationService for how these fields
 * are computed. statutory_employer_total/breakdown are EMPLOYER costs
 * (informational), never subtracted from net_pay.
 */
class Payslip extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'tenant_id', 'payroll_run_id', 'user_id',
        'basic_salary', 'allowances_total', 'allowances_breakdown', 'gross_pay',
        'statutory_employee_total', 'statutory_employee_breakdown', 'taxable_income', 'paye_amount',
        'other_deductions_total', 'deductions_breakdown', 'net_pay',
        'statutory_employer_total', 'statutory_employer_breakdown', 'employer_cost_total',
    ];

    protected $casts = [
        'allowances_breakdown' => 'array',
        'deductions_breakdown' => 'array',
        'statutory_employee_breakdown' => 'array',
        'statutory_employer_breakdown' => 'array',
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

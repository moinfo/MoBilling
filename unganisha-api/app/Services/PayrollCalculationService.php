<?php

namespace App\Services;

use App\Models\AllowanceSubscription;
use App\Models\AttendancePenalty;
use App\Models\DeductionSubscription;
use App\Models\EmployeeProfile;
use App\Models\Loan;
use App\Models\PayrollSettings;
use App\Models\SalaryAdvance;
use App\Models\StaffReportPenalty;
use App\Models\StaffSalary;
use App\Models\StatutoryRate;
use App\Models\StatutoryRateSubscription;
use App\Models\User;
use Carbon\Carbon;

/**
 * The payroll math, isolated from the controller so it's independently
 * testable. All figures are computed fresh here and then frozen onto a
 * Payslip row by the caller — this class itself never writes to the DB.
 *
 * IMPORTANT: statutory_employer_total (and each item's employer_percent
 * portion) are EMPLOYER costs — they must never be subtracted from
 * net_pay. Only statutory_employee_total, paye, and other_deductions
 * (subscribed deductions + attendance/report penalties) reduce net_pay.
 *
 * Statutory items (NSSF, WCF, SDL, or anything else a tenant adds, e.g.
 * NHIF) come from the tenant-configurable `statutory_rates` catalog, not
 * hardcoded fields — a StatutoryRateSubscription lets an individual
 * employee opt out of one (default subscribed/subject, matching how
 * Allowance/Deduction subscriptions already default). PAYE stays separate
 * (bracket-based, EmployeeProfile.subject_to_paye gates it) since it isn't
 * a percent-of-gross catalog item.
 */
class PayrollCalculationService
{
    /** @return array{basic_salary:float,allowances_total:float,allowances_breakdown:array,gross_pay:float,statutory_employee_total:float,statutory_employee_breakdown:array,taxable_income:float,paye_amount:float,other_deductions_total:float,deductions_breakdown:array,net_pay:float,statutory_employer_total:float,statutory_employer_breakdown:array,employer_cost_total:float}|null */
    public function computeForUser(User $user, string $monthKey): ?array
    {
        $periodEnd = Carbon::createFromFormat('Y-m', $monthKey)->endOfMonth();
        $periodStart = $periodEnd->copy()->startOfMonth();

        $salary = StaffSalary::effectiveFor($user->id, $periodEnd->toDateString());
        if (!$salary) {
            return null; // no salary on file yet — not eligible for this run
        }
        $basic = (float) $salary->basic_salary;

        [$allowancesTotal, $allowancesBreakdown] = $this->sumSubscriptions(
            AllowanceSubscription::withoutGlobalScopes()
                ->where('user_id', $user->id)->where('is_active', true)
                ->with('allowance')->get(),
            fn ($s) => $s->allowance,
            $basic,
        );

        $gross = round($basic + $allowancesTotal, 2);

        $profile = EmployeeProfile::withoutGlobalScopes()->where('user_id', $user->id)->first();
        $subjectToPaye = $profile?->subject_to_paye ?? true;

        [$statutoryEmployeeTotal, $statutoryEmployeeBreakdown, $statutoryEmployerTotal, $statutoryEmployerBreakdown, $taxableReduction] =
            $this->computeStatutoryRates($user, $gross);

        $taxableIncome = round($gross - $taxableReduction, 2);
        $settings = PayrollSettings::forTenant($user->tenant_id);
        $paye = $subjectToPaye ? $this->calculatePaye($taxableIncome, $settings->paye_brackets) : 0.0;

        [$subscribedDeductionsTotal, $deductionsBreakdown] = $this->sumSubscriptions(
            DeductionSubscription::withoutGlobalScopes()
                ->where('user_id', $user->id)->where('is_active', true)
                ->with('deduction')->get(),
            fn ($s) => $s->deduction,
            $basic,
        );

        $attendancePenalties = (float) AttendancePenalty::withoutGlobalScopes()
            ->where('user_id', $user->id)->where('waived', false)
            ->whereBetween('date', [$periodStart->toDateString(), $periodEnd->toDateString()])
            ->sum('amount');
        if ($attendancePenalties > 0) {
            $deductionsBreakdown[] = ['name' => 'Attendance Penalties', 'amount' => round($attendancePenalties, 2)];
        }

        $reportPenalties = (float) StaffReportPenalty::withoutGlobalScopes()
            ->where('user_id', $user->id)->where('waived', false)
            ->whereBetween('period_date', [$periodStart->toDateString(), $periodEnd->toDateString()])
            ->sum('amount');
        if ($reportPenalties > 0) {
            $deductionsBreakdown[] = ['name' => 'Late Report Penalties', 'amount' => round($reportPenalties, 2)];
        }

        $loanTotal = 0.0;
        foreach ($this->resolveLoanDeductions($user) as $ld) {
            $loanTotal += $ld['amount'];
            $deductionsBreakdown[] = ['name' => 'Loan Repayment', 'amount' => $ld['amount']];
        }

        $advanceTotal = 0.0;
        foreach ($this->resolveAdvanceRecoveries($user, $monthKey) as $ar) {
            $advanceTotal += $ar['amount'];
            $deductionsBreakdown[] = ['name' => 'Salary Advance Recovery', 'amount' => $ar['amount']];
        }

        $otherDeductionsTotal = round($subscribedDeductionsTotal + $attendancePenalties + $reportPenalties + $loanTotal + $advanceTotal, 2);

        $netPay = round($gross - $statutoryEmployeeTotal - $paye - $otherDeductionsTotal, 2);
        $employerCostTotal = round($gross + $statutoryEmployerTotal, 2);

        return [
            'basic_salary' => $basic,
            'allowances_total' => $allowancesTotal,
            'allowances_breakdown' => $allowancesBreakdown,
            'gross_pay' => $gross,
            'statutory_employee_total' => $statutoryEmployeeTotal,
            'statutory_employee_breakdown' => $statutoryEmployeeBreakdown,
            'taxable_income' => $taxableIncome,
            'paye_amount' => $paye,
            'other_deductions_total' => $otherDeductionsTotal,
            'deductions_breakdown' => $deductionsBreakdown,
            'net_pay' => $netPay,
            'statutory_employer_total' => $statutoryEmployerTotal,
            'statutory_employer_breakdown' => $statutoryEmployerBreakdown,
            'employer_cost_total' => $employerCostTotal,
        ];
    }

    /**
     * Loops every active StatutoryRate for the tenant, applying employee_
     * percent (deducted, and — if reduces_taxable_income — subtracted
     * before PAYE) and employer_percent (cost only, never deducted) for
     * each one the employee isn't individually opted out of.
     *
     * @return array{0:float,1:array,2:float,3:array,4:float} [employeeTotal, employeeBreakdown, employerTotal, employerBreakdown, taxableReduction]
     */
    private function computeStatutoryRates(User $user, float $gross): array
    {
        $rates = StatutoryRate::withoutGlobalScopes()
            ->where('tenant_id', $user->tenant_id)->where('is_active', true)
            ->orderBy('name')->get();

        $subscriptions = StatutoryRateSubscription::withoutGlobalScopes()
            ->where('user_id', $user->id)->get()->keyBy('statutory_rate_id');

        $employeeTotal = 0.0;
        $employeeBreakdown = [];
        $employerTotal = 0.0;
        $employerBreakdown = [];
        $taxableReduction = 0.0;

        foreach ($rates as $rate) {
            $sub = $subscriptions->get($rate->id);
            $subscribed = $sub ? (bool) $sub->is_active : true; // no row yet = subject by default

            if (!$subscribed) {
                continue;
            }

            $employeeAmount = round($gross * ((float) $rate->employee_percent) / 100, 2);
            $employerAmount = round($gross * ((float) $rate->employer_percent) / 100, 2);

            if ($employeeAmount > 0) {
                $employeeTotal += $employeeAmount;
                $employeeBreakdown[] = ['name' => $rate->name, 'amount' => $employeeAmount];
                if ($rate->reduces_taxable_income) {
                    $taxableReduction += $employeeAmount;
                }
            }

            if ($employerAmount > 0) {
                $employerTotal += $employerAmount;
                $employerBreakdown[] = ['name' => $rate->name, 'amount' => $employerAmount];
            }
        }

        return [round($employeeTotal, 2), $employeeBreakdown, round($employerTotal, 2), $employerBreakdown, round($taxableReduction, 2)];
    }

    /**
     * Read-only projection of what each active loan would collect this
     * period — never writes anything. finalize() calls this same method to
     * decide what to actually collect, so a draft preview and the real
     * collection can never drift apart.
     *
     * @return array<int, array{loan: Loan, amount: float}>
     */
    public function resolveLoanDeductions(User $user): array
    {
        $loans = Loan::withoutGlobalScopes()
            ->where('user_id', $user->id)->where('status', 'active')->where('balance', '>', 0)
            ->orderBy('issued_date')->get();

        $result = [];
        foreach ($loans as $loan) {
            $amount = round(min((float) $loan->monthly_installment, (float) $loan->balance), 2);
            if ($amount > 0) {
                $result[] = ['loan' => $loan, 'amount' => $amount];
            }
        }

        return $result;
    }

    /**
     * Read-only projection of pending advances recoverable this period
     * (recovery_month_key match) — never writes anything. Same
     * shared-source-of-truth reasoning as resolveLoanDeductions().
     *
     * @return array<int, array{advance: SalaryAdvance, amount: float}>
     */
    public function resolveAdvanceRecoveries(User $user, string $monthKey): array
    {
        $advances = SalaryAdvance::withoutGlobalScopes()
            ->where('user_id', $user->id)->where('status', 'pending')
            ->where('recovery_month_key', $monthKey)->get();

        $result = [];
        foreach ($advances as $advance) {
            $amount = round((float) $advance->amount, 2);
            if ($amount > 0) {
                $result[] = ['advance' => $advance, 'amount' => $amount];
            }
        }

        return $result;
    }

    /** Shared fixed/percent_of_basic resolution for both allowance and deduction subscriptions. */
    private function sumSubscriptions(iterable $subscriptions, callable $catalogItem, float $basic): array
    {
        $total = 0.0;
        $breakdown = [];

        foreach ($subscriptions as $sub) {
            $item = $catalogItem($sub);
            if (!$item || !$item->is_active) {
                continue;
            }

            $amount = $sub->amount_override !== null
                ? (float) $sub->amount_override
                : ($item->calculation_type === 'fixed'
                    ? (float) $item->default_amount
                    : round($basic * ((float) $item->default_amount) / 100, 2));

            $total += $amount;
            $breakdown[] = ['name' => $item->name, 'amount' => round($amount, 2)];
        }

        return [round($total, 2), $breakdown];
    }

    /** tax = base_deduction + rate% * (taxable_income - bracket.min), bracket where min <= income < max (max null = uncapped). */
    private function calculatePaye(float $taxableIncome, array $brackets): float
    {
        if ($taxableIncome <= 0) {
            return 0.0;
        }

        foreach ($brackets as $bracket) {
            $min = (float) $bracket['min'];
            $max = $bracket['max'] !== null ? (float) $bracket['max'] : null;

            if ($taxableIncome >= $min && ($max === null || $taxableIncome < $max)) {
                $tax = (float) $bracket['base_deduction'] + (((float) $bracket['rate']) / 100) * ($taxableIncome - $min);
                return round(max(0, $tax), 2);
            }
        }

        return 0.0;
    }
}

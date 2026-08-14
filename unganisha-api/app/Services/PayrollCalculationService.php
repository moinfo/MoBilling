<?php

namespace App\Services;

use App\Models\AllowanceSubscription;
use App\Models\AttendancePenalty;
use App\Models\DeductionSubscription;
use App\Models\PayrollSettings;
use App\Models\StaffReportPenalty;
use App\Models\StaffSalary;
use App\Models\User;
use Carbon\Carbon;

/**
 * The payroll math, isolated from the controller so it's independently
 * testable. All figures are computed fresh here and then frozen onto a
 * Payslip row by the caller — this class itself never writes to the DB.
 *
 * IMPORTANT: nssf_employer/wcf/sdl are EMPLOYER costs — they must never be
 * subtracted from net_pay. Only nssf_employee, paye, and other_deductions
 * (subscribed deductions + attendance/report penalties) reduce net_pay.
 */
class PayrollCalculationService
{
    /** @return array{basic_salary:float,allowances_total:float,allowances_breakdown:array,gross_pay:float,nssf_employee_amount:float,taxable_income:float,paye_amount:float,other_deductions_total:float,deductions_breakdown:array,net_pay:float,nssf_employer_amount:float,wcf_amount:float,sdl_amount:float,employer_cost_total:float}|null */
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

        $settings = PayrollSettings::forTenant($user->tenant_id);

        $nssfEmployee = round($gross * ((float) $settings->nssf_employee_percent) / 100, 2);
        $taxableIncome = round($gross - $nssfEmployee, 2);
        $paye = $this->calculatePaye($taxableIncome, $settings->paye_brackets);

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

        $otherDeductionsTotal = round($subscribedDeductionsTotal + $attendancePenalties + $reportPenalties, 2);

        $netPay = round($gross - $nssfEmployee - $paye - $otherDeductionsTotal, 2);

        $nssfEmployer = round($gross * ((float) $settings->nssf_employer_percent) / 100, 2);
        $wcf = round($gross * ((float) $settings->wcf_percent) / 100, 2);
        $sdl = round($gross * ((float) $settings->sdl_percent) / 100, 2);
        $employerCostTotal = round($gross + $nssfEmployer + $wcf + $sdl, 2);

        return [
            'basic_salary' => $basic,
            'allowances_total' => $allowancesTotal,
            'allowances_breakdown' => $allowancesBreakdown,
            'gross_pay' => $gross,
            'nssf_employee_amount' => $nssfEmployee,
            'taxable_income' => $taxableIncome,
            'paye_amount' => $paye,
            'other_deductions_total' => $otherDeductionsTotal,
            'deductions_breakdown' => $deductionsBreakdown,
            'net_pay' => $netPay,
            'nssf_employer_amount' => $nssfEmployer,
            'wcf_amount' => $wcf,
            'sdl_amount' => $sdl,
            'employer_cost_total' => $employerCostTotal,
        ];
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

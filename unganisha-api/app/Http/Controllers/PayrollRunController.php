<?php

namespace App\Http\Controllers;

use App\Models\PayrollRun;
use App\Models\Payslip;
use App\Models\User;
use App\Services\LoanService;
use App\Services\PayrollCalculationService;
use App\Traits\AuthorizesPermissions;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class PayrollRunController extends Controller
{
    use AuthorizesPermissions;

    public function index()
    {
        $this->authorizePermission('payroll.manage', 'payroll.view');
        $tenantId = auth()->user()->tenant_id;

        $runs = PayrollRun::where('tenant_id', $tenantId)
            ->withCount('payslips')
            ->orderByDesc('month_key')
            ->get();

        return response()->json(['data' => $runs]);
    }

    public function show(PayrollRun $payrollRun)
    {
        $this->authorizePermission('payroll.manage', 'payroll.view');
        if ($payrollRun->tenant_id !== auth()->user()->tenant_id) {
            return response()->json(['message' => 'Not found'], 404);
        }

        return response()->json(['data' => $payrollRun->load([
            'payslips.user:id,name',
            'payslips.user.employeeProfile:user_id,tin_number,bank_name,bank_account_number',
            'generatedBy:id,name',
            'finalizedBy:id,name',
        ])]);
    }

    /** Creates the run (if new) and one Payslip per active employee with a StaffSalary on file. Re-runnable while draft. */
    public function generate(Request $request, PayrollCalculationService $calculator)
    {
        $this->authorizePermission('payroll.manage');
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'month_key' => 'required|regex:/^\d{4}-\d{2}$/',
        ]);

        $existing = PayrollRun::where('tenant_id', $tenantId)->where('month_key', $data['month_key'])->first();
        if ($existing && $existing->status === 'finalized') {
            return response()->json(['message' => "Payroll for {$data['month_key']} is already finalized — it can no longer be regenerated."], 422);
        }

        $run = DB::transaction(function () use ($tenantId, $data, $existing, $calculator) {
            $run = $existing ?? PayrollRun::create([
                'tenant_id' => $tenantId,
                'month_key' => $data['month_key'],
                'status' => 'draft',
                'generated_by' => auth()->id(),
                'generated_at' => now(),
            ]);

            // A user already in this draft (regardless of current is_active)
            // must stay eligible for recomputation — they earned this period's
            // pay while active; deactivating them afterward (e.g. they left
            // the company) must never make a re-generate silently drop their
            // payslip. Only *newly* adding someone to a run requires them to
            // currently be active.
            $previousUserIds = $existing
                ? Payslip::where('payroll_run_id', $run->id)->pluck('user_id')->all()
                : [];

            if ($existing) {
                $run->update(['generated_by' => auth()->id(), 'generated_at' => now()]);
                Payslip::where('payroll_run_id', $run->id)->delete();
            }

            $users = User::where('tenant_id', $tenantId)
                ->where(fn ($q) => $q->where('is_active', true)->orWhereIn('id', $previousUserIds))
                ->get();
            foreach ($users as $user) {
                $result = $calculator->computeForUser($user, $data['month_key']);
                if ($result === null) {
                    continue; // no salary on file — skip
                }
                Payslip::create(array_merge($result, [
                    'tenant_id' => $tenantId,
                    'payroll_run_id' => $run->id,
                    'user_id' => $user->id,
                ]));
            }

            return $run;
        });

        return response()->json([
            'data' => $run->load('payslips.user:id,name'),
            'message' => "Generated {$run->payslips()->count()} payslip(s) for {$data['month_key']}.",
        ], $existing ? 200 : 201);
    }

    /**
     * Finalizing is the one true collection point: it re-resolves the same
     * loan/advance projections computeForUser() used to build the last
     * generated payslips and actually collects them (Loan.balance decrement
     * + LoanPayment ledger row, SalaryAdvance -> recovered). Never done
     * during generate()/computeForUser(), which stay read-only, so
     * regenerating a draft can never double-apply or silently skip a
     * collection.
     */
    public function finalize(PayrollRun $payrollRun, PayrollCalculationService $calculator, LoanService $loanService)
    {
        $this->authorizePermission('payroll.manage');
        if ($payrollRun->tenant_id !== auth()->user()->tenant_id) {
            return response()->json(['message' => 'Not found'], 404);
        }
        if ($payrollRun->status === 'finalized') {
            return response()->json(['message' => 'Already finalized.'], 422);
        }
        if ($payrollRun->payslips()->count() === 0) {
            return response()->json(['message' => 'Cannot finalize a run with no payslips.'], 422);
        }

        DB::transaction(function () use ($payrollRun, $calculator, $loanService) {
            $payrollRun->update([
                'status' => 'finalized',
                'finalized_by' => auth()->id(),
                'finalized_at' => now(),
            ]);

            $payslips = $payrollRun->payslips()->with('user')->get();
            foreach ($payslips as $payslip) {
                if (!$payslip->user) {
                    continue;
                }

                foreach ($calculator->resolveLoanDeductions($payslip->user) as $ld) {
                    $loanService->recordPayment($ld['loan'], $ld['amount'], $payrollRun->id, auth()->id());
                }

                foreach ($calculator->resolveAdvanceRecoveries($payslip->user, $payrollRun->month_key) as $ar) {
                    $ar['advance']->update(['status' => 'recovered']);
                }
            }
        });

        return response()->json(['data' => $payrollRun]);
    }

    /** Only while draft — a finalized run is payroll history and must not be erasable (Payslips cascade-delete with it). */
    public function destroy(PayrollRun $payrollRun)
    {
        $this->authorizePermission('payroll.manage');
        if ($payrollRun->tenant_id !== auth()->user()->tenant_id) {
            return response()->json(['message' => 'Not found'], 404);
        }
        if ($payrollRun->status === 'finalized') {
            return response()->json(['message' => 'Cannot delete a finalized payroll run.'], 422);
        }

        $payrollRun->delete();

        return response()->json(null, 204);
    }
}

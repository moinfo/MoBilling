<?php

namespace App\Http\Controllers;

use App\Models\PayrollRun;
use App\Models\Payslip;
use App\Models\User;
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

        return response()->json(['data' => $payrollRun->load(['payslips.user:id,name', 'generatedBy:id,name', 'finalizedBy:id,name'])]);
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

            if ($existing) {
                $run->update(['generated_by' => auth()->id(), 'generated_at' => now()]);
                Payslip::where('payroll_run_id', $run->id)->delete();
            }

            $users = User::where('tenant_id', $tenantId)->where('is_active', true)->get();
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

    public function finalize(PayrollRun $payrollRun)
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

        $payrollRun->update([
            'status' => 'finalized',
            'finalized_by' => auth()->id(),
            'finalized_at' => now(),
        ]);

        return response()->json(['data' => $payrollRun]);
    }
}

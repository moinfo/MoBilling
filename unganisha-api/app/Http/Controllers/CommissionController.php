<?php

namespace App\Http\Controllers;

use App\Models\Commission;
use App\Models\Payslip;
use App\Models\PayrollRun;
use App\Services\PayrollCalculationService;
use App\Traits\AuthorizesPermissions;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class CommissionController extends Controller
{
    use AuthorizesPermissions;

    public function index(Request $request)
    {
        $this->authorizePermission('payroll.manage', 'payroll.view');
        $tenantId = auth()->user()->tenant_id;

        $query = Commission::with('user:id,name')->where('tenant_id', $tenantId)->orderByDesc('earned_date');

        if ($request->user_id) {
            $query->where('user_id', $request->user_id);
        }

        return response()->json(['data' => $query->get()]);
    }

    public function store(Request $request, PayrollCalculationService $calculator)
    {
        $this->authorizePermission('payroll.manage');
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'user_id' => ['required', 'uuid', Rule::exists('users', 'id')->where('tenant_id', $tenantId)],
            'amount' => 'required|numeric|min:0.01',
            'earned_date' => 'required|date',
            'payout_month_key' => 'required|regex:/^\d{4}-\d{2}$/',
            'notes' => 'nullable|string|max:1000',
        ]);

        $run = PayrollRun::where('tenant_id', $tenantId)->where('month_key', $data['payout_month_key'])->first();
        if ($run && $run->status === 'finalized') {
            return response()->json(['message' => "Payroll for {$data['payout_month_key']} is already finalized — pick a later payout month."], 422);
        }

        $data['tenant_id'] = $tenantId;
        $data['status'] = 'pending';
        $data['created_by'] = auth()->id();

        $commission = Commission::create($data);

        // A draft payslip for this employee/month is a frozen snapshot taken
        // at "generate" time — it won't know about a commission added after
        // that, so refresh it now instead of leaving it to look un-applied
        // until someone happens to hit the per-payslip "Recompute" button.
        if ($run) {
            $payslip = Payslip::where('payroll_run_id', $run->id)->where('user_id', $data['user_id'])->first();
            if ($payslip) {
                $result = $calculator->computeForUser($commission->user, $data['payout_month_key']);
                if ($result !== null) {
                    $payslip->update($result);
                }
            }
        }

        return response()->json(['data' => $commission->load('user:id,name')], 201);
    }

    public function show(Commission $commission)
    {
        $this->authorizePermission('payroll.manage', 'payroll.view');
        if ($commission->tenant_id !== auth()->user()->tenant_id) {
            return response()->json(['message' => 'Not found'], 404);
        }

        return response()->json(['data' => $commission->load('user:id,name')]);
    }

    public function cancel(Commission $commission, PayrollCalculationService $calculator)
    {
        $this->authorizePermission('payroll.manage');
        if ($commission->tenant_id !== auth()->user()->tenant_id) {
            return response()->json(['message' => 'Not found'], 404);
        }
        if ($commission->status !== 'pending') {
            return response()->json(['message' => 'Only a pending commission can be cancelled.'], 422);
        }

        $commission->update(['status' => 'cancelled']);

        // Mirror store(): a draft payslip may have already been computed
        // with this commission folded into gross — drop it from the
        // snapshot now rather than leaving a cancelled commission's amount
        // sitting in someone's pay until the next unrelated recompute.
        $run = PayrollRun::where('tenant_id', $commission->tenant_id)
            ->where('month_key', $commission->payout_month_key)->first();
        if ($run && $run->status !== 'finalized') {
            $payslip = Payslip::where('payroll_run_id', $run->id)->where('user_id', $commission->user_id)->first();
            if ($payslip) {
                $result = $calculator->computeForUser($commission->user, $commission->payout_month_key);
                if ($result !== null) {
                    $payslip->update($result);
                }
            }
        }

        return response()->json(['data' => $commission]);
    }
}

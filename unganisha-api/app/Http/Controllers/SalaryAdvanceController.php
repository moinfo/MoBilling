<?php

namespace App\Http\Controllers;

use App\Models\PayrollRun;
use App\Models\SalaryAdvance;
use App\Traits\AuthorizesPermissions;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class SalaryAdvanceController extends Controller
{
    use AuthorizesPermissions;

    public function index(Request $request)
    {
        $this->authorizePermission('payroll.manage', 'payroll.view');
        $tenantId = auth()->user()->tenant_id;

        $query = SalaryAdvance::with('user:id,name')->where('tenant_id', $tenantId)->orderByDesc('issued_date');

        if ($request->user_id) {
            $query->where('user_id', $request->user_id);
        }

        return response()->json(['data' => $query->get()]);
    }

    public function store(Request $request)
    {
        $this->authorizePermission('payroll.manage');
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'user_id' => ['required', 'uuid', Rule::exists('users', 'id')->where('tenant_id', $tenantId)],
            'amount' => 'required|numeric|min:0.01',
            'issued_date' => 'required|date',
            'recovery_month_key' => 'required|regex:/^\d{4}-\d{2}$/',
            'notes' => 'nullable|string|max:1000',
        ]);

        $finalized = PayrollRun::where('tenant_id', $tenantId)
            ->where('month_key', $data['recovery_month_key'])->where('status', 'finalized')->exists();
        if ($finalized) {
            return response()->json(['message' => "Payroll for {$data['recovery_month_key']} is already finalized — pick a later recovery month."], 422);
        }

        $data['tenant_id'] = $tenantId;
        $data['status'] = 'pending';
        $data['created_by'] = auth()->id();

        $advance = SalaryAdvance::create($data);

        return response()->json(['data' => $advance->load('user:id,name')], 201);
    }

    public function show(SalaryAdvance $salaryAdvance)
    {
        $this->authorizePermission('payroll.manage', 'payroll.view');
        if ($salaryAdvance->tenant_id !== auth()->user()->tenant_id) {
            return response()->json(['message' => 'Not found'], 404);
        }

        return response()->json(['data' => $salaryAdvance->load('user:id,name')]);
    }

    public function cancel(SalaryAdvance $salaryAdvance)
    {
        $this->authorizePermission('payroll.manage');
        if ($salaryAdvance->tenant_id !== auth()->user()->tenant_id) {
            return response()->json(['message' => 'Not found'], 404);
        }
        if ($salaryAdvance->status !== 'pending') {
            return response()->json(['message' => 'Only a pending advance can be cancelled.'], 422);
        }

        $salaryAdvance->update(['status' => 'cancelled']);

        return response()->json(['data' => $salaryAdvance]);
    }
}

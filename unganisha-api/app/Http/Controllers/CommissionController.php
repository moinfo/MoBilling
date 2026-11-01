<?php

namespace App\Http\Controllers;

use App\Models\Commission;
use App\Models\PayrollRun;
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

    public function store(Request $request)
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

        $finalized = PayrollRun::where('tenant_id', $tenantId)
            ->where('month_key', $data['payout_month_key'])->where('status', 'finalized')->exists();
        if ($finalized) {
            return response()->json(['message' => "Payroll for {$data['payout_month_key']} is already finalized — pick a later payout month."], 422);
        }

        $data['tenant_id'] = $tenantId;
        $data['status'] = 'pending';
        $data['created_by'] = auth()->id();

        $commission = Commission::create($data);

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

    public function cancel(Commission $commission)
    {
        $this->authorizePermission('payroll.manage');
        if ($commission->tenant_id !== auth()->user()->tenant_id) {
            return response()->json(['message' => 'Not found'], 404);
        }
        if ($commission->status !== 'pending') {
            return response()->json(['message' => 'Only a pending commission can be cancelled.'], 422);
        }

        $commission->update(['status' => 'cancelled']);

        return response()->json(['data' => $commission]);
    }
}

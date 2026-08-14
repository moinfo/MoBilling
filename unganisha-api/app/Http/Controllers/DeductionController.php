<?php

namespace App\Http\Controllers;

use App\Models\Deduction;
use App\Models\DeductionSubscription;
use App\Models\User;
use App\Traits\AuthorizesPermissions;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class DeductionController extends Controller
{
    use AuthorizesPermissions;

    public function index()
    {
        $this->authorizePermission('payroll.manage', 'payroll.view');

        return response()->json(['data' => Deduction::where('is_active', true)->orderBy('name')->get()]);
    }

    public function store(Request $request)
    {
        $this->authorizePermission('payroll.manage');

        $data = $request->validate([
            'name' => 'required|string|max:255',
            'calculation_type' => 'required|in:fixed,percent_of_basic',
            'default_amount' => 'required|numeric|min:0',
        ]);
        $data['tenant_id'] = auth()->user()->tenant_id;

        return response()->json(['data' => Deduction::create($data)], 201);
    }

    public function update(Request $request, Deduction $deduction)
    {
        $this->authorizePermission('payroll.manage');
        if ($deduction->tenant_id !== auth()->user()->tenant_id) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $data = $request->validate([
            'name' => 'required|string|max:255',
            'calculation_type' => 'required|in:fixed,percent_of_basic',
            'default_amount' => 'required|numeric|min:0',
            'is_active' => 'boolean',
        ]);

        $deduction->update($data);

        return response()->json(['data' => $deduction]);
    }

    public function destroy(Deduction $deduction)
    {
        $this->authorizePermission('payroll.manage');
        if ($deduction->tenant_id !== auth()->user()->tenant_id) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $deduction->delete();

        return response()->json(null, 204);
    }

    public function subscriptions(Deduction $deduction)
    {
        $this->authorizePermission('payroll.manage', 'payroll.view');
        if ($deduction->tenant_id !== auth()->user()->tenant_id) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $users = User::where('tenant_id', $deduction->tenant_id)->where('is_active', true)->orderBy('name')->get(['id', 'name']);
        $subs = DeductionSubscription::where('deduction_id', $deduction->id)->get()->keyBy('user_id');

        return response()->json(['data' => ['users' => $users, 'subscriptions' => $subs]]);
    }

    public function subscribe(Request $request, Deduction $deduction)
    {
        $this->authorizePermission('payroll.manage');
        $tenantId = auth()->user()->tenant_id;
        if ($deduction->tenant_id !== $tenantId) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $data = $request->validate([
            'user_id' => ['required', 'uuid', Rule::exists('users', 'id')->where('tenant_id', $tenantId)],
            'amount_override' => 'nullable|numeric|min:0',
            'is_active' => 'boolean',
        ]);

        $sub = DeductionSubscription::updateOrCreate(
            ['user_id' => $data['user_id'], 'deduction_id' => $deduction->id],
            ['tenant_id' => $tenantId, 'amount_override' => $data['amount_override'] ?? null, 'is_active' => $data['is_active'] ?? true],
        );

        return response()->json(['data' => $sub]);
    }
}

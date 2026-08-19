<?php

namespace App\Http\Controllers;

use App\Models\Allowance;
use App\Models\AllowanceSubscription;
use App\Models\User;
use App\Traits\AuthorizesPermissions;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class AllowanceController extends Controller
{
    use AuthorizesPermissions;

    public function index()
    {
        $this->authorizePermission('payroll.manage', 'payroll.view');

        return response()->json(['data' => Allowance::where('is_active', true)->orderBy('name')->get()]);
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

        return response()->json(['data' => Allowance::create($data)], 201);
    }

    public function update(Request $request, Allowance $allowance)
    {
        $this->authorizePermission('payroll.manage');
        if ($allowance->tenant_id !== auth()->user()->tenant_id) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $data = $request->validate([
            'name' => 'required|string|max:255',
            'calculation_type' => 'required|in:fixed,percent_of_basic',
            'default_amount' => 'required|numeric|min:0',
            'is_active' => 'boolean',
        ]);

        $allowance->update($data);

        return response()->json(['data' => $allowance]);
    }

    public function destroy(Allowance $allowance)
    {
        $this->authorizePermission('payroll.manage');
        if ($allowance->tenant_id !== auth()->user()->tenant_id) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $allowance->delete();

        return response()->json(null, 204);
    }

    /** Every employee + whether/how they're subscribed to this allowance — for the assignment UI. */
    public function subscriptions(Allowance $allowance)
    {
        $this->authorizePermission('payroll.manage', 'payroll.view');
        if ($allowance->tenant_id !== auth()->user()->tenant_id) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $users = User::where('tenant_id', $allowance->tenant_id)->where('is_active', true)->orderBy('name')->get(['id', 'name']);
        $subs = AllowanceSubscription::where('allowance_id', $allowance->id)->get()->keyBy('user_id');

        return response()->json(['data' => ['users' => $users, 'subscriptions' => $subs]]);
    }

    public function subscribe(Request $request, Allowance $allowance)
    {
        $this->authorizePermission('payroll.manage');
        $tenantId = auth()->user()->tenant_id;
        if ($allowance->tenant_id !== $tenantId) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $data = $request->validate([
            'user_id' => ['required', 'uuid', Rule::exists('users', 'id')->where('tenant_id', $tenantId)],
            'amount_override' => 'nullable|numeric|min:0',
            'is_active' => 'boolean',
        ]);

        $sub = AllowanceSubscription::updateOrCreate(
            ['user_id' => $data['user_id'], 'allowance_id' => $allowance->id],
            ['tenant_id' => $tenantId, 'amount_override' => $data['amount_override'] ?? null, 'is_active' => $data['is_active'] ?? true],
        );

        return response()->json(['data' => $sub]);
    }
}

<?php

namespace App\Http\Controllers;

use App\Models\StatutoryRate;
use App\Models\StatutoryRateSubscription;
use App\Models\User;
use App\Traits\AuthorizesPermissions;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class StatutoryRateController extends Controller
{
    use AuthorizesPermissions;

    public function index()
    {
        $this->authorizePermission('payroll.manage', 'payroll.view');

        return response()->json(['data' => StatutoryRate::where('is_active', true)->orderBy('name')->get()]);
    }

    public function store(Request $request)
    {
        $this->authorizePermission('payroll.manage');

        $data = $request->validate([
            'name' => 'required|string|max:255',
            'employee_percent' => 'required|numeric|min:0|max:100',
            'employer_percent' => 'required|numeric|min:0|max:100',
            'reduces_taxable_income' => 'boolean',
        ]);
        $data['tenant_id'] = auth()->user()->tenant_id;

        return response()->json(['data' => StatutoryRate::create($data)], 201);
    }

    public function update(Request $request, StatutoryRate $statutoryRate)
    {
        $this->authorizePermission('payroll.manage');
        if ($statutoryRate->tenant_id !== auth()->user()->tenant_id) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $data = $request->validate([
            'name' => 'required|string|max:255',
            'employee_percent' => 'required|numeric|min:0|max:100',
            'employer_percent' => 'required|numeric|min:0|max:100',
            'reduces_taxable_income' => 'boolean',
            'is_active' => 'boolean',
        ]);

        $statutoryRate->update($data);

        return response()->json(['data' => $statutoryRate]);
    }

    public function destroy(StatutoryRate $statutoryRate)
    {
        $this->authorizePermission('payroll.manage');
        if ($statutoryRate->tenant_id !== auth()->user()->tenant_id) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $statutoryRate->delete();

        return response()->json(null, 204);
    }

    /** Every employee + whether they're subscribed (subject to) this statutory rate — default subject, opt-out. */
    public function subscriptions(StatutoryRate $statutoryRate)
    {
        $this->authorizePermission('payroll.manage', 'payroll.view');
        if ($statutoryRate->tenant_id !== auth()->user()->tenant_id) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $users = User::where('tenant_id', $statutoryRate->tenant_id)->where('is_active', true)->orderBy('name')->get(['id', 'name']);
        $subs = StatutoryRateSubscription::where('statutory_rate_id', $statutoryRate->id)->get()->keyBy('user_id');

        return response()->json(['data' => ['users' => $users, 'subscriptions' => $subs]]);
    }

    public function subscribe(Request $request, StatutoryRate $statutoryRate)
    {
        $this->authorizePermission('payroll.manage');
        $tenantId = auth()->user()->tenant_id;
        if ($statutoryRate->tenant_id !== $tenantId) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $data = $request->validate([
            'user_id' => ['required', 'uuid', Rule::exists('users', 'id')->where('tenant_id', $tenantId)],
            'is_active' => 'boolean',
        ]);

        $sub = StatutoryRateSubscription::updateOrCreate(
            ['user_id' => $data['user_id'], 'statutory_rate_id' => $statutoryRate->id],
            ['tenant_id' => $tenantId, 'is_active' => $data['is_active'] ?? true],
        );

        return response()->json(['data' => $sub]);
    }
}

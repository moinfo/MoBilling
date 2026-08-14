<?php

namespace App\Http\Controllers;

use App\Models\LeaveBalance;
use App\Models\LeaveType;
use App\Models\User;
use App\Traits\AuthorizesPermissions;
use Illuminate\Http\Request;

class LeaveTypeController extends Controller
{
    use AuthorizesPermissions;

    public function index()
    {
        // Read-only listing (needed to populate the "request leave" form) is
        // open to anyone who can reach /leave at all — only mutating it is
        // restricted to leave.manage.
        return response()->json(['data' => LeaveType::where('is_active', true)->orderBy('name')->get()]);
    }

    public function store(Request $request)
    {
        $this->authorizePermission('leave.manage');

        $data = $request->validate([
            'name' => 'required|string|max:255',
            'days_per_year' => 'required|integer|min:0|max:365',
            'is_paid' => 'boolean',
            'color' => 'nullable|string|max:20',
        ]);
        $data['tenant_id'] = auth()->user()->tenant_id;

        $leaveType = LeaveType::create($data);

        return response()->json(['data' => $leaveType], 201);
    }

    public function update(Request $request, LeaveType $leaveType)
    {
        $this->authorizePermission('leave.manage');
        if ($leaveType->tenant_id !== auth()->user()->tenant_id) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $data = $request->validate([
            'name' => 'required|string|max:255',
            'days_per_year' => 'required|integer|min:0|max:365',
            'is_paid' => 'boolean',
            'is_active' => 'boolean',
            'color' => 'nullable|string|max:20',
        ]);

        $leaveType->update($data);

        return response()->json(['data' => $leaveType]);
    }

    public function destroy(LeaveType $leaveType)
    {
        $this->authorizePermission('leave.manage');
        if ($leaveType->tenant_id !== auth()->user()->tenant_id) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $leaveType->delete();

        return response()->json(null, 204);
    }

    /** HR sets/updates one employee's allocated days for a leave type/year. */
    public function setBalance(Request $request)
    {
        $this->authorizePermission('leave.manage');
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'user_id' => ['required', 'uuid', \Illuminate\Validation\Rule::exists('users', 'id')->where('tenant_id', $tenantId)],
            'leave_type_id' => ['required', 'uuid', \Illuminate\Validation\Rule::exists('leave_types', 'id')->where('tenant_id', $tenantId)],
            'year' => 'required|integer|min:2020|max:2100',
            'allocated_days' => 'required|integer|min:0|max:365',
        ]);

        $balance = LeaveBalance::updateOrCreate(
            ['user_id' => $data['user_id'], 'leave_type_id' => $data['leave_type_id'], 'year' => $data['year']],
            ['tenant_id' => $tenantId, 'allocated_days' => $data['allocated_days']],
        );

        return response()->json(['data' => $balance]);
    }

    /** HR-admin view: every employee's balances for a given year. */
    public function balances(Request $request)
    {
        $this->authorizePermission('leave.manage');
        $tenantId = auth()->user()->tenant_id;
        $year = (int) $request->query('year', now()->year);

        $balances = LeaveBalance::with('leaveType')
            ->where('tenant_id', $tenantId)->where('year', $year)->get();

        $users = User::where('tenant_id', $tenantId)->where('is_active', true)->orderBy('name')->get(['id', 'name']);

        return response()->json(['data' => [
            'year' => $year,
            'users' => $users,
            'balances' => $balances,
        ]]);
    }
}

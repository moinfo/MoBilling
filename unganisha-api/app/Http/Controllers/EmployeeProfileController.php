<?php

namespace App\Http\Controllers;

use App\Models\EmployeeProfile;
use App\Models\User;
use App\Traits\AuthorizesPermissions;
use Illuminate\Http\Request;

class EmployeeProfileController extends Controller
{
    use AuthorizesPermissions;

    /** HR-admin list: every active staff member + their profile, if any. */
    public function index(Request $request)
    {
        $this->authorizePermission('employees.read');
        $tenantId = auth()->user()->tenant_id;

        $query = User::where('tenant_id', $tenantId)->with('employeeProfile', 'role');

        if ($search = $request->query('search')) {
            $query->where(function ($q) use ($search) {
                $q->where('name', 'like', "%{$search}%")->orWhere('email', 'like', "%{$search}%");
            });
        }

        $users = $query->orderBy('name')->paginate($request->query('per_page', 20));

        return response()->json($users);
    }

    /** One staff member's profile (HR-admin view). */
    public function show(User $user)
    {
        $this->authorizePermission('employees.read');
        if ($user->tenant_id !== auth()->user()->tenant_id) {
            return response()->json(['message' => 'Not found'], 404);
        }

        return response()->json(['data' => [
            'user' => $user->load('role', 'supervisor'),
            'profile' => $user->employeeProfile,
        ]]);
    }

    /** Create/update one staff member's profile — one row per user, no separate store endpoint. */
    public function update(Request $request, User $user)
    {
        $this->authorizePermission('employees.update');
        if ($user->tenant_id !== auth()->user()->tenant_id) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $data = $request->validate([
            'employee_number' => 'nullable|string|max:100',
            'hire_date' => 'nullable|date',
            'department' => 'nullable|string|max:255',
            'position' => 'nullable|string|max:255',
            'employment_type' => 'nullable|in:full_time,part_time,contract,intern',
            'national_id' => 'nullable|string|max:100',
            'nssf_number' => 'nullable|string|max:100',
            'tin_number' => 'nullable|string|max:100',
            'date_of_birth' => 'nullable|date',
            'gender' => 'nullable|string|max:50',
            'next_of_kin_name' => 'nullable|string|max:255',
            'next_of_kin_phone' => 'nullable|string|max:50',
            'bank_name' => 'nullable|string|max:255',
            'bank_branch' => 'nullable|string|max:255',
            'bank_account_name' => 'nullable|string|max:255',
            'bank_account_number' => 'nullable|string|max:100',
            'mobile_money_provider' => 'nullable|string|max:100',
            'mobile_money_number' => 'nullable|string|max:50',
            'termination_date' => 'nullable|date',
            'notes' => 'nullable|string|max:2000',
            'subject_to_paye' => 'sometimes|boolean',
        ]);

        $profile = EmployeeProfile::updateOrCreate(
            ['user_id' => $user->id],
            array_merge($data, ['tenant_id' => $user->tenant_id]),
        );

        return response()->json(['data' => $profile]);
    }

    /** Self-service: the logged-in user's own profile, read-only here. */
    public function mine()
    {
        $user = auth()->user();

        return response()->json(['data' => [
            'user' => $user->load('role', 'supervisor'),
            'profile' => $user->employeeProfile,
        ]]);
    }
}

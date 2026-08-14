<?php

namespace App\Http\Controllers;

use App\Models\StaffSalary;
use App\Traits\AuthorizesPermissions;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class StaffSalaryController extends Controller
{
    use AuthorizesPermissions;

    public function index(Request $request)
    {
        $this->authorizePermission('payroll.manage', 'payroll.view');
        $tenantId = auth()->user()->tenant_id;

        $query = StaffSalary::with('user:id,name')->where('tenant_id', $tenantId)->orderByDesc('effective_from');

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
            'basic_salary' => 'required|numeric|min:0',
            'effective_from' => 'required|date',
            'notes' => 'nullable|string|max:1000',
        ]);
        $data['tenant_id'] = $tenantId;

        $salary = StaffSalary::create($data);

        return response()->json(['data' => $salary->load('user:id,name')], 201);
    }

    public function destroy(StaffSalary $staffSalary)
    {
        $this->authorizePermission('payroll.manage');
        if ($staffSalary->tenant_id !== auth()->user()->tenant_id) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $staffSalary->delete();

        return response()->json(null, 204);
    }
}

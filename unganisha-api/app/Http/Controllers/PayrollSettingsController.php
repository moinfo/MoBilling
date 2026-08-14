<?php

namespace App\Http\Controllers;

use App\Models\PayrollSettings;
use App\Traits\AuthorizesPermissions;
use Illuminate\Http\Request;

class PayrollSettingsController extends Controller
{
    use AuthorizesPermissions;

    public function show()
    {
        $this->authorizePermission('payroll.manage', 'payroll.view');

        return response()->json(['data' => PayrollSettings::forTenant(auth()->user()->tenant_id)]);
    }

    public function update(Request $request)
    {
        $this->authorizePermission('payroll.manage');

        $data = $request->validate([
            'paye_brackets' => 'required|array|min:1',
            'paye_brackets.*.min' => 'required|numeric|min:0',
            'paye_brackets.*.max' => 'nullable|numeric|gt:paye_brackets.*.min',
            'paye_brackets.*.rate' => 'required|numeric|min:0|max:100',
            'paye_brackets.*.base_deduction' => 'required|numeric|min:0',
            'nssf_employee_percent' => 'required|numeric|min:0|max:100',
            'nssf_employer_percent' => 'required|numeric|min:0|max:100',
            'wcf_percent' => 'required|numeric|min:0|max:100',
            'sdl_percent' => 'required|numeric|min:0|max:100',
        ]);

        $settings = PayrollSettings::forTenant(auth()->user()->tenant_id);
        $settings->update($data);

        return response()->json(['data' => $settings]);
    }
}

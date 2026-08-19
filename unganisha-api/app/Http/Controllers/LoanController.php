<?php

namespace App\Http\Controllers;

use App\Models\Loan;
use App\Traits\AuthorizesPermissions;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class LoanController extends Controller
{
    use AuthorizesPermissions;

    public function index(Request $request)
    {
        $this->authorizePermission('payroll.manage', 'payroll.view');
        $tenantId = auth()->user()->tenant_id;

        $query = Loan::with('user:id,name')->where('tenant_id', $tenantId)->orderByDesc('issued_date');

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
            'principal' => 'required|numeric|min:0.01',
            'monthly_installment' => 'required|numeric|min:0.01',
            'issued_date' => 'required|date',
            'notes' => 'nullable|string|max:1000',
        ]);
        $data['tenant_id'] = $tenantId;
        $data['balance'] = $data['principal'];
        $data['status'] = 'active';
        $data['created_by'] = auth()->id();

        $loan = Loan::create($data);

        return response()->json(['data' => $loan->load('user:id,name')], 201);
    }

    public function show(Loan $loan)
    {
        $this->authorizePermission('payroll.manage', 'payroll.view');
        if ($loan->tenant_id !== auth()->user()->tenant_id) {
            return response()->json(['message' => 'Not found'], 404);
        }

        return response()->json(['data' => $loan->load('user:id,name')]);
    }

    /** The loan's LoanPayment ledger — audit trail of every repayment collected. */
    public function payments(Loan $loan)
    {
        $this->authorizePermission('payroll.manage', 'payroll.view');
        if ($loan->tenant_id !== auth()->user()->tenant_id) {
            return response()->json(['message' => 'Not found'], 404);
        }

        return response()->json(['data' => $loan->payments()->with('payrollRun:id,month_key')->orderByDesc('created_at')->get()]);
    }

    /** Only while untouched — once a repayment has been collected, cancelling would corrupt the ledger. */
    public function cancel(Loan $loan)
    {
        $this->authorizePermission('payroll.manage');
        if ($loan->tenant_id !== auth()->user()->tenant_id) {
            return response()->json(['message' => 'Not found'], 404);
        }
        if ((float) $loan->balance !== (float) $loan->principal) {
            return response()->json(['message' => 'Cannot cancel a loan that already has payments recorded.'], 422);
        }

        $loan->update(['status' => 'cancelled']);

        return response()->json(['data' => $loan]);
    }
}

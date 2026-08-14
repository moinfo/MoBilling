<?php

namespace App\Http\Controllers;

use App\Models\Payslip;
use App\Services\PdfService;
use App\Traits\AuthorizesPermissions;

class PayslipController extends Controller
{
    use AuthorizesPermissions;

    public function show(Payslip $payslip)
    {
        $this->authorizePermission('payroll.manage', 'payroll.view');
        if ($payslip->tenant_id !== auth()->user()->tenant_id) {
            return response()->json(['message' => 'Not found'], 404);
        }

        return response()->json(['data' => $payslip->load(['user:id,name', 'payrollRun:id,month_key,status'])]);
    }

    public function downloadPdf(Payslip $payslip, PdfService $pdfService)
    {
        $this->authorizePermission('payroll.manage', 'payroll.view');
        if ($payslip->tenant_id !== auth()->user()->tenant_id) {
            return response()->json(['message' => 'Not found'], 404);
        }

        return $this->streamPdf($payslip, $pdfService);
    }

    /** Self-service: an employee's own payslips (list + download own), no permission required. */
    public function mine()
    {
        $payslips = Payslip::where('user_id', auth()->id())
            ->with('payrollRun:id,month_key,status')
            ->whereHas('payrollRun', fn ($q) => $q->where('status', 'finalized'))
            ->orderByDesc('created_at')
            ->get();

        return response()->json(['data' => $payslips]);
    }

    public function downloadMinePdf(Payslip $payslip, PdfService $pdfService)
    {
        if ($payslip->user_id !== auth()->id()) {
            return response()->json(['message' => 'Not found'], 404);
        }
        if ($payslip->payrollRun->status !== 'finalized') {
            return response()->json(['message' => 'This payslip is not finalized yet.'], 422);
        }

        return $this->streamPdf($payslip, $pdfService);
    }

    private function streamPdf(Payslip $payslip, PdfService $pdfService)
    {
        $pdf = $pdfService->generatePayslip($payslip);
        $slug = \Illuminate\Support\Str::slug($payslip->user->name) . '-' . $payslip->payrollRun->month_key;

        return $pdf->download("payslip-{$slug}.pdf");
    }
}

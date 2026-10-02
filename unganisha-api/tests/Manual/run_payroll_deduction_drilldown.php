<?php
// php tests/Manual/run_payroll_deduction_drilldown.php  (live DB, rolled back at the end)
require __DIR__ . '/../../vendor/autoload.php';
$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Http\Controllers\AttendanceController;
use App\Http\Controllers\PayrollRunController;
use App\Models\{AttendancePenalty, PayrollRun, Payslip, Tenant, User};
use App\Services\PayrollCalculationService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

$fail = 0;
function ok($c, $m) { global $fail; if (!$c) { $fail++; echo "FAIL $m\n"; } else echo "PASS $m\n"; }
function req(Request $rq, $u) { $rq->setUserResolver(fn () => $u); app()->instance('request', $rq); auth()->setUser($u); return $rq; }
function trap(callable $f) {
    try { return $f(); }
    catch (\Illuminate\Validation\ValidationException $e) { return response()->json(['errors' => $e->errors(), 'message' => $e->getMessage()], 422); }
    catch (\Symfony\Component\HttpKernel\Exception\HttpExceptionInterface $e) { return response()->json(['message' => $e->getMessage()], $e->getStatusCode()); }
}

DB::beginTransaction();
try {
    $tenant = Tenant::find('019c8f39-679e-70d2-af92-ac72a25b0d9c'); // Moinfotech Company Limited
    $owner = User::where('tenant_id', $tenant->id)->where('is_active', true)->get()->first(fn ($u) => $u->hasPermission('payroll.manage'));
    ok((bool) $owner, 'have a payroll.manage user to test with');

    $ctl = app(PayrollRunController::class);
    $calc = app(PayrollCalculationService::class);
    $run = PayrollRun::where('tenant_id', $tenant->id)->where('month_key', '2026-09')->first();
    ok((bool) $run, 'the 2026-09 draft run exists for this tenant');

    $slip = Payslip::where('payroll_run_id', $run->id)
        ->whereHas('user', fn ($q) => $q->where('name', 'khajira tangira'))->first();
    ok((bool) $slip, 'found a payslip to drill into');

    // 1. deduction-items exposes the real underlying rows (not just the frozen breakdown).
    req(Request::create('/x', 'GET'), $owner);
    $r1 = trap(fn () => $ctl->payslipDeductionItems($run, $slip));
    $items1 = $r1->getData(true)['data'];
    $unwaived = array_values(array_filter($items1['attendance'], fn ($i) => !$i['waived']));
    ok(count($unwaived) > 0, 'has at least one unwaived attendance item to waive');
    $target = $unwaived[0];

    // 2. Waive it via the EXISTING attendance endpoint — this controller never duplicates that logic.
    $attCtl = app(AttendanceController::class);
    $penalty = AttendancePenalty::find($target['id']);
    trap(fn () => $attCtl->waivePenalty(req(Request::create('/x', 'POST', ['reason' => 'drilldown test']), $owner), $penalty));
    ok($penalty->fresh()->waived === true, 'the item is now waived via the existing single-item endpoint');

    // 3. recomputePayslip() refreshes just this payslip in place.
    $oldTotal = collect($slip->deductions_breakdown)->firstWhere('name', 'Attendance Penalties')['amount'] ?? 0;
    $r2 = trap(fn () => $ctl->recomputePayslip($run, $slip, $calc));
    ok($r2->status() === 200, 'recomputePayslip returns 200: got ' . $r2->status());
    $updated = $r2->getData(true)['data'];
    ok($updated['id'] === $slip->id, 'recompute updates the SAME payslip row (same id), not a new one');
    $newTotal = collect($updated['deductions_breakdown'])->firstWhere('name', 'Attendance Penalties')['amount'] ?? 0;
    ok($newTotal == $oldTotal - $target['amount'], "the total dropped by exactly the waived amount: {$oldTotal} -> {$newTotal}");

    // 4. A finalized run cannot be recomputed.
    $run->status = 'finalized'; // in-memory only inside this transaction, never saved beyond rollback
    $run->save();
    $r3 = trap(fn () => $ctl->recomputePayslip($run, $slip, $calc));
    ok($r3->status() === 422, 'recompute on a finalized run is rejected (422): got ' . $r3->status());

    // 5. A payslip from a mismatched run 404s (parent/child integrity).
    $run->status = 'draft';
    $run->save();
    $otherRun = PayrollRun::where('tenant_id', $tenant->id)->where('id', '!=', $run->id)->first();
    $r4 = trap(fn () => $ctl->payslipDeductionItems($otherRun, $slip));
    ok($r4->status() === 404, 'mismatched run/payslip 404s: got ' . $r4->status());

    echo $fail === 0 ? "\nALL PASS\n" : "\n{$fail} FAILURE(S)\n";
} finally {
    DB::rollBack();
    echo "Rolled back — no permanent changes.\n";
}

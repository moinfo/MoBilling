<?php
// php tests/Manual/run_staff_report_bulk_waive.php  (live DB, rolled back at the end)
require __DIR__ . '/../../vendor/autoload.php';
$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Http\Controllers\StaffReportsController;
use App\Models\{StaffReportPenalty, Tenant, User};
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

$fail = 0;
function ok($c, $m) { global $fail; if (!$c) { $fail++; echo "FAIL $m\n"; } else echo "PASS $m\n"; }
function j($r) { return $r->getData(true); }
function req(Request $rq, $u) { $rq->setUserResolver(fn () => $u); app()->instance('request', $rq); auth()->setUser($u); return $rq; }
function trap(callable $f) {
    try { return $f(); }
    catch (\Illuminate\Validation\ValidationException $e) { return response()->json(['errors' => $e->errors(), 'message' => $e->getMessage()], 422); }
    catch (\Symfony\Component\HttpKernel\Exception\HttpExceptionInterface $e) { return response()->json(['message' => $e->getMessage()], $e->getStatusCode()); }
}

DB::beginTransaction();
try {
    $tenant = Tenant::find('019c8f39-679e-70d2-af92-ac72a25b0d9c'); // Moinfotech Company Limited
    $activeUsers = User::where('tenant_id', $tenant->id)->where('is_active', true)->get();
    $owner = $activeUsers->first(fn ($u) => $u->hasPermission('staff_reports.review'));
    $staff = $activeUsers->first(fn ($u) => !$u->hasPermission('staff_reports.review') && $u->id !== $owner?->id);
    ok($owner && $staff, 'have a staff_reports.review reviewer and a plain staff member to test with');

    $ctl = app(StaffReportsController::class);

    $dates = ['2026-09-20', '2026-09-21', '2026-09-22'];
    foreach ($dates as $d) {
        StaffReportPenalty::where('user_id', $staff->id)->where('period_date', $d)->delete();
    }
    $p1 = StaffReportPenalty::create(['tenant_id' => $tenant->id, 'user_id' => $staff->id, 'report_type' => 'daily', 'penalty_type' => 'missing', 'period_date' => $dates[0], 'amount' => 2000, 'waived' => false]);
    $p2 = StaffReportPenalty::create(['tenant_id' => $tenant->id, 'user_id' => $staff->id, 'report_type' => 'daily', 'penalty_type' => 'missing', 'period_date' => $dates[1], 'amount' => 2000, 'waived' => false]);
    $p3 = StaffReportPenalty::create(['tenant_id' => $tenant->id, 'user_id' => $staff->id, 'report_type' => 'daily', 'penalty_type' => 'missing', 'period_date' => $dates[2], 'amount' => 2000, 'waived' => true, 'waived_by' => $owner->id, 'waived_at' => now()]);

    // 1. Non-reviewer is blocked.
    $r1 = trap(fn () => $ctl->bulkWaivePenalty(req(Request::create('/api/staff-reports/penalties/bulk-waive', 'POST', [
        'ids' => [$p1->id, $p2->id],
    ]), $staff)));
    ok($r1->status() === 403, 'a non-reviewer cannot bulk-waive (403): got ' . $r1->status());

    // 2. Reviewer bulk-waives: 2 unwaived + 1 already-waived -> skipped, not errored.
    $r2 = trap(fn () => $ctl->bulkWaivePenalty(req(Request::create('/api/staff-reports/penalties/bulk-waive', 'POST', [
        'ids' => [$p1->id, $p2->id, $p3->id], 'reason' => 'bulk test',
    ]), $owner)));
    ok($r2->status() === 200, 'bulkWaivePenalty returns 200: got ' . $r2->status());
    $data2 = j($r2);
    ok(($data2['waived'] ?? null) === 2 && ($data2['skipped'] ?? null) === 1, 'waived=2, skipped=1 (the already-waived one): got ' . json_encode($data2));
    ok($p1->fresh()->waived === true && $p2->fresh()->waived === true, 'both unwaived ones are now waived');
    ok($p1->fresh()->waive_reason === 'bulk test', 'waive_reason stored on each waived row');

    // 3. An id outside the reviewer's scope (different tenant) is skipped, not touched.
    $otherTenant = Tenant::where('id', '!=', $tenant->id)->first();
    $otherUser = User::where('tenant_id', $otherTenant->id)->first();
    $pOther = StaffReportPenalty::create(['tenant_id' => $otherTenant->id, 'user_id' => $otherUser->id, 'report_type' => 'daily', 'penalty_type' => 'missing', 'period_date' => '2026-09-23', 'amount' => 2000, 'waived' => false]);
    $r3 = trap(fn () => $ctl->bulkWaivePenalty(req(Request::create('/api/staff-reports/penalties/bulk-waive', 'POST', [
        'ids' => [$pOther->id],
    ]), $owner)));
    $data3 = j($r3);
    ok(($data3['waived'] ?? null) === 0 && ($data3['skipped'] ?? null) === 1, 'an out-of-scope id is skipped, not errored: got ' . json_encode($data3));
    ok($pOther->fresh()->waived === false, 'the out-of-scope row was not touched');

    echo $fail === 0 ? "\nALL PASS\n" : "\n{$fail} FAILURE(S)\n";
} finally {
    DB::rollBack();
    echo "Rolled back — no permanent changes.\n";
}

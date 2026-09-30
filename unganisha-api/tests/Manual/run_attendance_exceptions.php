<?php
// php tests/Manual/run_attendance_exceptions.php  (live DB, rolled back at the end)
require __DIR__ . '/../../vendor/autoload.php';
$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Http\Controllers\AttendanceExceptionController;
use App\Models\{Attendance, AttendanceExceptionRequest, AttendancePenalty, Tenant, User};
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
    $tenant = Tenant::find('019c8f39-679e-70d2-af92-ac72a25b0d9c'); // Moinfotech Company Limited — real multi-staff tenant
    $activeUsers = User::where('tenant_id', $tenant->id)->where('is_active', true)->get();
    $owner = $activeUsers->first(fn ($u) => $u->hasPermission('attendance.manage'));
    $staff = $activeUsers->first(fn ($u) => !$u->hasPermission('attendance.manage') && $u->id !== $owner?->id)
        ?? $activeUsers->first(fn ($u) => $u->id !== $owner?->id);
    ok($staff && $owner && $staff->id !== $owner->id, 'have two distinct active users to test with (owner has attendance.manage, staff does not)');

    $ctl = app(AttendanceExceptionController::class);
    $date = now()->subDays(5)->toDateString();
    AttendanceExceptionRequest::where('user_id', $staff->id)->where('date', $date)->delete();
    Attendance::where('user_id', $staff->id)->whereDate('date', $date)->delete();
    AttendancePenalty::where('user_id', $staff->id)->whereDate('date', $date)->delete();
    $pen = AttendancePenalty::create(['tenant_id' => $tenant->id, 'user_id' => $staff->id, 'date' => $date, 'penalty_type' => 'absent', 'amount' => 5000, 'notes' => 'test', 'waived' => false]);

    // 1. Self-service store() — staff explains their own flagged day.
    $r1 = trap(fn () => $ctl->store(req(Request::create('/api/attendance-exceptions', 'POST', [
        'date' => $date, 'type' => 'field', 'comment' => 'Test: client site visit',
    ]), $staff)));
    ok($r1->status() === 201, 'store() returns 201');
    $excId = j($r1)['data']['id'] ?? null;
    ok($excId && AttendanceExceptionRequest::find($excId)?->status === 'pending', 'exception row created as pending');

    // 2. Duplicate pending request for the same day is rejected.
    $r2 = trap(fn () => $ctl->store(req(Request::create('/api/attendance-exceptions', 'POST', [
        'date' => $date, 'type' => 'leave', 'comment' => 'Second attempt',
    ]), $staff)));
    ok($r2->status() === 422, 'a second pending request for the same day is rejected (422): got ' . $r2->status());

    // 3. review() by a user without attendance.manage is blocked.
    $exc = AttendanceExceptionRequest::find($excId);
    $r3 = trap(fn () => $ctl->review(req(Request::create("/api/attendance-exceptions/{$excId}/review", 'POST', [
        'decision' => 'approved',
    ]), $staff), $exc));
    ok($r3->status() === 403, 'a non-attendance.manage user cannot review (403): got ' . $r3->status());
    ok(AttendanceExceptionRequest::find($excId)->status === 'pending', 'still pending after the blocked attempt');

    // 4. review() approve by the owner (has attendance.manage) actually excuses the day + drops the penalty.
    ok((bool) $owner->hasPermission('attendance.manage'), 'owner user actually holds attendance.manage (test precondition)');
    $r4 = trap(fn () => $ctl->review(req(Request::create("/api/attendance-exceptions/{$excId}/review", 'POST', [
        'decision' => 'approved', 'review_note' => 'Confirmed with client',
    ]), $owner), $exc));
    ok($r4->status() === 200, 'review() approve returns 200: got ' . $r4->status());
    $exc->refresh();
    ok($exc->status === 'approved' && $exc->reviewed_by === $owner->id, 'exception row now approved + reviewed_by set');
    $att = Attendance::where('user_id', $staff->id)->whereDate('date', $date)->first();
    ok($att && $att->status === 'field', 'Attendance row now status=field (excused)');
    ok(AttendancePenalty::where('user_id', $staff->id)->whereDate('date', $date)->where('waived', false)->count() === 0, 'the stale penalty was dropped by the approval');

    // 5. Deciding an already-decided request is rejected.
    $r5 = trap(fn () => $ctl->review(req(Request::create("/api/attendance-exceptions/{$excId}/review", 'POST', [
        'decision' => 'rejected',
    ]), $owner), $exc));
    ok($r5->status() === 422, 're-reviewing an already-decided request is rejected (422): got ' . $r5->status());

    // 6. A rejected request does NOT touch the day.
    $date2 = now()->subDays(6)->toDateString();
    AttendanceExceptionRequest::where('user_id', $staff->id)->where('date', $date2)->delete();
    Attendance::where('user_id', $staff->id)->whereDate('date', $date2)->delete();
    $r6 = trap(fn () => $ctl->store(req(Request::create('/api/attendance-exceptions', 'POST', [
        'date' => $date2, 'type' => 'leave', 'comment' => 'Test reject path',
    ]), $staff)));
    $excId2 = j($r6)['data']['id'];
    $exc2 = AttendanceExceptionRequest::find($excId2);
    $r7 = trap(fn () => $ctl->review(req(Request::create("/api/attendance-exceptions/{$excId2}/review", 'POST', [
        'decision' => 'rejected', 'review_note' => 'Not valid',
    ]), $owner), $exc2));
    ok($r7->status() === 200, 'review() reject returns 200');
    ok(Attendance::where('user_id', $staff->id)->whereDate('date', $date2)->doesntExist(), 'a rejected request creates no Attendance row');

    // 7. index() visibility: staff sees only their own; owner sees all (including staff's).
    $r8 = trap(fn () => $ctl->index(req(Request::create('/api/attendance-exceptions', 'GET'), $staff)));
    $staffRows = j($r8)['data'];
    ok(collect($staffRows)->every(fn ($row) => $row['user']['id'] === $staff->id), 'a plain staff member only sees their own exception requests');

    $r9 = trap(fn () => $ctl->index(req(Request::create('/api/attendance-exceptions', 'GET'), $owner)));
    $ownerRows = j($r9)['data'];
    ok(collect($ownerRows)->contains(fn ($row) => $row['id'] === $excId), 'attendance.manage holder sees the staff member\'s request too');

    // 8. cancel() by someone else is blocked; cancel() of a pending-own request works.
    $date3 = now()->subDays(7)->toDateString();
    AttendanceExceptionRequest::where('user_id', $staff->id)->where('date', $date3)->delete();
    $r10 = trap(fn () => $ctl->store(req(Request::create('/api/attendance-exceptions', 'POST', [
        'date' => $date3, 'type' => 'leave', 'comment' => 'Cancel-path test',
    ]), $staff)));
    $excId3 = j($r10)['data']['id'];
    $exc3 = AttendanceExceptionRequest::find($excId3);
    req(Request::create("/api/attendance-exceptions/{$excId3}/cancel", 'POST'), $owner);
    $r11 = trap(fn () => $ctl->cancel($exc3));
    ok($r11->status() === 403, 'a different user cannot cancel someone else\'s request (403): got ' . $r11->status());
    req(Request::create("/api/attendance-exceptions/{$excId3}/cancel", 'POST'), $staff);
    $r12 = trap(fn () => $ctl->cancel($exc3));
    ok($r12->status() === 200, 'the requester can cancel their own pending request');
    ok(AttendanceExceptionRequest::find($excId3) === null, 'cancelled request row is deleted');

    echo $fail === 0 ? "\nALL PASS\n" : "\n{$fail} FAILURE(S)\n";
} finally {
    DB::rollBack();
    echo "Rolled back — no permanent changes.\n";
}

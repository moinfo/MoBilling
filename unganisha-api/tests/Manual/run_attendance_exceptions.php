<?php
// php tests/Manual/run_attendance_exceptions.php  (live DB, rolled back at the end)
require __DIR__ . '/../../vendor/autoload.php';
$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Http\Controllers\AttendanceExceptionController;
use App\Models\{Attendance, AttendanceExceptionRequest, AttendancePenalty, AttendanceSettings, Tenant, User};
use Carbon\Carbon;
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

// Explanation window is date-math sensitive (1st–Nth of the month AFTER the
// flagged day), so freeze "now" at a fixed point where the window math is
// unambiguous regardless of which real-world day this script runs on.
Carbon::setTestNow('2026-10-03 10:00:00'); // within Sept's window (Oct 1–5, default 5 days)

DB::beginTransaction();
try {
    $tenant = Tenant::find('019c8f39-679e-70d2-af92-ac72a25b0d9c'); // Moinfotech Company Limited — real multi-staff tenant
    $activeUsers = User::where('tenant_id', $tenant->id)->where('is_active', true)->get();
    $owner = $activeUsers->first(fn ($u) => $u->hasPermission('attendance.manage'));
    $staff = $activeUsers->first(fn ($u) => !$u->hasPermission('attendance.manage') && $u->id !== $owner?->id)
        ?? $activeUsers->first(fn ($u) => $u->id !== $owner?->id);
    ok($staff && $owner && $staff->id !== $owner->id, 'have two distinct active users to test with (owner has attendance.manage, staff does not)');

    // Admin opens a window: Oct 1–5, reviewing September. "Now" is frozen
    // at Oct 3 below, so this window is open for the rest of this script.
    AttendanceSettings::withoutGlobalScopes()->where('tenant_id', $tenant->id)->update([
        'exception_window_from' => '2026-10-01',
        'exception_window_to' => '2026-10-05',
        'exception_review_month' => '2026-09-01',
    ]);

    $ctl = app(AttendanceExceptionController::class);
    $date = '2026-09-27'; // September — explainable now that "now" is Oct 3
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

    // 2b. update() lets the requester edit their own still-pending
    // explanation (comment/type) before it's decided — but no one else
    // can, and not once it's been decided.
    $exc = AttendanceExceptionRequest::find($excId);
    $r2b = trap(fn () => $ctl->update(req(Request::create("/api/attendance-exceptions/{$excId}", 'PUT', [
        'type' => 'field', 'comment' => 'Edited: actually it was something else',
    ]), $owner), $exc));
    ok($r2b->status() === 403, "a non-owner cannot edit someone else's pending request (403): got " . $r2b->status());
    ok($exc->fresh()->comment === 'Test: client site visit', 'comment unchanged after the blocked edit attempt');

    // Keep type=field so downstream steps (which assert the approved day
    // ends up status=field) are unaffected — only the comment changes here.
    $r2c = trap(fn () => $ctl->update(req(Request::create("/api/attendance-exceptions/{$excId}", 'PUT', [
        'type' => 'field', 'comment' => 'Edited: actually it was something else',
    ]), $staff), $exc));
    ok($r2c->status() === 200, 'the requester can edit their own pending request: got ' . $r2c->status());
    $exc->refresh();
    ok($exc->comment === 'Edited: actually it was something else', 'edit actually changed the comment');

    // 3. review() by a user without attendance.manage is blocked.
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
    $date2 = '2026-09-26';
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

    // 6b. 'other' type on approval: waives the deduction but does NOT
    // touch the Attendance row/status (unlike leave/field).
    $date2b = '2026-09-25';
    AttendanceExceptionRequest::where('user_id', $staff->id)->where('date', $date2b)->delete();
    Attendance::where('user_id', $staff->id)->whereDate('date', $date2b)->delete();
    AttendancePenalty::where('user_id', $staff->id)->whereDate('date', $date2b)->delete();
    $att2b = Attendance::create(['tenant_id' => $tenant->id, 'user_id' => $staff->id, 'date' => $date2b, 'check_in_at' => null, 'check_out_at' => null]);
    $pen2b = AttendancePenalty::create(['tenant_id' => $tenant->id, 'user_id' => $staff->id, 'date' => $date2b, 'penalty_type' => 'absent', 'amount' => 5000, 'notes' => 'test', 'waived' => false]);
    $r6b = trap(fn () => $ctl->store(req(Request::create('/api/attendance-exceptions', 'POST', [
        'date' => $date2b, 'type' => 'other', 'comment' => 'Car broke down on the way',
    ]), $staff)));
    ok($r6b->status() === 201, "'other' type is accepted by store(): got " . $r6b->status());
    $excId2b = j($r6b)['data']['id'];
    $exc2b = AttendanceExceptionRequest::find($excId2b);
    $r7b = trap(fn () => $ctl->review(req(Request::create("/api/attendance-exceptions/{$excId2b}/review", 'POST', [
        'decision' => 'approved', 'review_note' => 'One-off, approved',
    ]), $owner), $exc2b));
    ok($r7b->status() === 200, "'other' approve returns 200: got " . $r7b->status());
    ok($att2b->fresh()->status === null, "'other' approval leaves Attendance::status untouched (still null, not excused)");
    $pen2b->refresh();
    ok($pen2b->waived === true && $pen2b->waived_by === $owner->id, "'other' approval waives the penalty (waived=true, waived_by=owner)");
    ok($pen2b->waive_reason === 'One-off, approved', "'other' approval uses the review_note as the waive_reason");

    // 7. index() visibility: staff sees only their own; owner sees all (including staff's).
    $r8 = trap(fn () => $ctl->index(req(Request::create('/api/attendance-exceptions', 'GET'), $staff)));
    $staffRows = j($r8)['data'];
    ok(collect($staffRows)->every(fn ($row) => $row['user']['id'] === $staff->id), 'a plain staff member only sees their own exception requests');

    $r9 = trap(fn () => $ctl->index(req(Request::create('/api/attendance-exceptions', 'GET'), $owner)));
    $ownerRows = j($r9)['data'];
    ok(collect($ownerRows)->contains(fn ($row) => $row['id'] === $excId), 'attendance.manage holder sees the staff member\'s request too');

    // 8. cancel() by someone else is blocked; cancel() of a pending-own request works.
    $date3 = '2026-09-24';
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

    // 9. Explanation window: "now" is frozen at 2026-10-03, admin opened
    // Oct 1–5 reviewing September — an August day is out of the reviewed
    // month, and an October day is out of the reviewed month too (even
    // though "now" is inside the open date range).
    $wrongMonthOld = '2026-08-15';
    AttendanceExceptionRequest::where('user_id', $staff->id)->where('date', $wrongMonthOld)->delete();
    $r13 = trap(fn () => $ctl->store(req(Request::create('/api/attendance-exceptions', 'POST', [
        'date' => $wrongMonthOld, 'type' => 'leave', 'comment' => 'Wrong month — August',
    ]), $staff)));
    ok($r13->status() === 422, "explaining an August day while reviewing September is rejected (422): got " . $r13->status());

    $wrongMonthNew = '2026-10-02';
    AttendanceExceptionRequest::where('user_id', $staff->id)->where('date', $wrongMonthNew)->delete();
    $r14 = trap(fn () => $ctl->store(req(Request::create('/api/attendance-exceptions', 'POST', [
        'date' => $wrongMonthNew, 'type' => 'leave', 'comment' => 'Wrong month — October',
    ]), $staff)));
    ok($r14->status() === 422, "explaining an October day while reviewing September is rejected (422): got " . $r14->status());

    // Right month, but "now" is outside the open date range.
    AttendanceSettings::withoutGlobalScopes()->where('tenant_id', $tenant->id)->update(['exception_window_to' => '2026-10-02']);
    $dateOutsideRange = '2026-09-20';
    AttendanceExceptionRequest::where('user_id', $staff->id)->where('date', $dateOutsideRange)->delete();
    $r15 = trap(fn () => $ctl->store(req(Request::create('/api/attendance-exceptions', 'POST', [
        'date' => $dateOutsideRange, 'type' => 'leave', 'comment' => 'Window narrowed to close before today',
    ]), $staff)));
    ok($r15->status() === 422, "right month but 'now' (Oct 3) is past the narrowed window (to Oct 2) — rejected (422): got " . $r15->status());
    AttendanceSettings::withoutGlobalScopes()->where('tenant_id', $tenant->id)->update(['exception_window_to' => '2026-10-05']);

    // No window configured at all (any field null) = closed, not open.
    AttendanceSettings::withoutGlobalScopes()->where('tenant_id', $tenant->id)->update(['exception_review_month' => null]);
    $dateNoWindow = '2026-09-19';
    AttendanceExceptionRequest::where('user_id', $staff->id)->where('date', $dateNoWindow)->delete();
    $r16 = trap(fn () => $ctl->store(req(Request::create('/api/attendance-exceptions', 'POST', [
        'date' => $dateNoWindow, 'type' => 'leave', 'comment' => 'No window configured',
    ]), $staff)));
    ok($r16->status() === 422, "an unconfigured window (null review month) defaults to closed (422): got " . $r16->status());
    AttendanceSettings::withoutGlobalScopes()->where('tenant_id', $tenant->id)->update(['exception_review_month' => '2026-09-01']);

    // 10. bulkReview(): attendance.manage-only, decides every pending id in
    // one call and skips (without erroring) any already-decided one.
    $bulkDates = ['2026-09-10', '2026-09-11', '2026-09-12'];
    foreach ($bulkDates as $bd) {
        AttendanceExceptionRequest::where('user_id', $staff->id)->where('date', $bd)->delete();
    }
    $b1 = AttendanceExceptionRequest::create(['tenant_id' => $tenant->id, 'user_id' => $staff->id, 'date' => $bulkDates[0], 'type' => 'leave', 'comment' => 'bulk a', 'status' => 'pending']);
    $b2 = AttendanceExceptionRequest::create(['tenant_id' => $tenant->id, 'user_id' => $staff->id, 'date' => $bulkDates[1], 'type' => 'field', 'comment' => 'bulk b', 'status' => 'pending']);
    $b3 = AttendanceExceptionRequest::create(['tenant_id' => $tenant->id, 'user_id' => $staff->id, 'date' => $bulkDates[2], 'type' => 'leave', 'comment' => 'bulk c', 'status' => 'approved', 'reviewed_by' => $owner->id, 'reviewed_at' => now()]);

    $r17 = trap(fn () => $ctl->bulkReview(req(Request::create('/api/attendance-exceptions/bulk-review', 'POST', [
        'ids' => [$b1->id, $b2->id], 'decision' => 'approved',
    ]), $staff)));
    ok($r17->status() === 403, 'a non-attendance.manage user cannot bulk-review (403): got ' . $r17->status());

    $r18 = trap(fn () => $ctl->bulkReview(req(Request::create('/api/attendance-exceptions/bulk-review', 'POST', [
        'ids' => [$b1->id, $b2->id, $b3->id], 'decision' => 'approved', 'review_note' => 'bulk ok',
    ]), $owner)));
    ok($r18->status() === 200, 'bulkReview returns 200: got ' . $r18->status());
    $bulkData = j($r18);
    ok(($bulkData['decided'] ?? null) === 2 && ($bulkData['skipped'] ?? null) === 1, 'bulkReview decided=2, skipped=1 (the already-approved one): got ' . json_encode($bulkData));
    ok($b1->fresh()->status === 'approved' && $b2->fresh()->status === 'approved', 'both pending ids are now approved');
    ok(
        Attendance::where('user_id', $staff->id)->whereDate('date', $bulkDates[0])->first()?->status === 'leave'
        && Attendance::where('user_id', $staff->id)->whereDate('date', $bulkDates[1])->first()?->status === 'field',
        'bulkReview applies each item\'s own type correctly (leave vs field)'
    );

    echo $fail === 0 ? "\nALL PASS\n" : "\n{$fail} FAILURE(S)\n";
} finally {
    DB::rollBack();
    Carbon::setTestNow();
    echo "Rolled back — no permanent changes.\n";
}

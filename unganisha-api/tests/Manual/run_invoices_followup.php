<?php
// php tests/Manual/run_invoices_followup.php
// Live DB, EVERY scenario rolled back. Notifications faked (Http::fake + preventStrayRequests as a
// belt-and-braces guard even though nothing here calls out). Never sends anything real.
//
// Covers: the Invoices-page "Follow-up" column/button/modal (FollowupController::summary, the
// create-then-log-call flow, DocumentController's followup=overdue filter, tenant isolation,
// permission gating) AND the admin-notification / staff-reminder / on-time-tracking additions
// (FollowupController::logCall notifications, followups:remind-staff, staffPerformance).
require __DIR__ . '/../../vendor/autoload.php';
$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Http\Controllers\DocumentController;
use App\Http\Controllers\FollowupController;
use App\Http\Middleware\CheckPermission;
use App\Models\{Client, CollectionAssignment, Document, Followup, Permission, Role, Tenant, User};
use App\Notifications\{FollowupAssignedNotification, FollowupReminderDigestNotification, FollowupResponseLoggedNotification, FollowupUnassignedNotification};
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\{Artisan, DB, Http, Notification};

$fail = 0;
function ok($c, $m) { global $fail; if (!$c) { $fail++; echo "FAIL $m\n"; } else echo "PASS $m\n"; }

Http::preventStrayRequests();
Http::fake();

$tenant = Tenant::withoutGlobalScopes()->where('name', 'MoBilling Test Co')->firstOrFail();
$admin = User::withoutGlobalScopes()->where('tenant_id', $tenant->id)->firstOrFail(); // seeded 'admin' role: has menu.followups, field_visits.log, documents.approve_collection

function scenario(string $title, callable $fn) {
    global $fail, $tenant, $admin;
    echo "== $title\n";
    DB::beginTransaction();
    try {
        auth()->login($admin);
        Notification::fake();
        $fn();
    } catch (\Throwable $e) {
        $fail++; echo "FAIL exception: " . $e->getMessage() . ' @' . basename($e->getFile()) . ':' . $e->getLine() . "\n";
    } finally {
        DB::rollBack();
        auth()->logout();
        Carbon::setTestNow();
    }
}

function fc(): FollowupController { return app(FollowupController::class); }
function dc(): DocumentController { return app(DocumentController::class); }

function call(callable $f): array {
    try {
        $res = $f();
        // DocumentController::index returns a Resource collection, not a JsonResponse, when called
        // directly (outside the router pipeline) — convert it the same way the HTTP kernel would.
        $json = method_exists($res, 'response') ? $res->response() : $res;
        return [$json->getStatusCode(), $json->getData(true)];
    } catch (\Illuminate\Validation\ValidationException $e) {
        return [422, ['message' => json_encode($e->errors())]];
    } catch (\Symfony\Component\HttpKernel\Exception\HttpException $e) {
        return [$e->getStatusCode(), ['message' => $e->getMessage()]];
    } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
        // Mirrors what the real HTTP kernel does with a failed implicit route-model bind (e.g. a
        // Followup filtered out by another tenant's BelongsToTenant scope) — these tests call
        // controller methods directly, so nothing else converts this to a 404 for us.
        return [404, ['message' => 'Not found.']];
    }
}

function mkClient(string $name = 'Followup Client'): Client {
    global $tenant;
    return Client::create(['tenant_id' => $tenant->id, 'name' => $name . ' ' . uniqid(), 'phone' => '2557' . random_int(10000000, 99999999), 'email' => uniqid() . '@example.test', 'status' => 'active']);
}

function mkInvoice(Client $client, float $total = 100000, int $dueDaysAgo = 10): Document {
    global $tenant;
    return Document::create([
        'tenant_id' => $tenant->id, 'client_id' => $client->id, 'type' => 'invoice',
        'document_number' => 'FUX-' . uniqid(), 'date' => now()->subDays($dueDaysAgo + 5)->toDateString(),
        'due_date' => now()->subDays($dueDaysAgo)->toDateString(),
        'subtotal' => $total, 'tax_amount' => 0, 'total' => $total, 'status' => 'overdue',
    ]);
}

function approve(Document $doc, User $by): void {
    $doc->update(['collection_reviewed_at' => now(), 'collection_reviewed_by' => $by->id]);
}

function mkRole(string $name, array $permNames): Role {
    global $tenant;
    $role = Role::create(['tenant_id' => $tenant->id, 'name' => $name . '-' . uniqid(), 'label' => $name]);
    $role->permissions()->attach(Permission::whereIn('name', $permNames)->pluck('id'));
    return $role;
}

function mkStaff(string $name, ?Role $role): User {
    global $tenant;
    return User::create([
        'tenant_id' => $tenant->id, 'name' => $name, 'email' => strtolower(str_replace(' ', '.', $name)) . uniqid() . '@example.test',
        'password' => 'x', 'role' => 'user', 'role_id' => $role?->id, 'is_active' => true,
    ]);
}

function permCheck(User $u, string $perm): int {
    $rq = Request::create('/x', 'GET');
    $rq->setUserResolver(fn () => $u);
    return (new CheckPermission())->handle($rq, fn () => response('ok'), $perm)->getStatusCode();
}

// ---------------------------------------------------------------------------
scenario('semantics: store() creates ONE row; logCall() updates it + spawns the next row (a call log, not a single mutable row)', function () {
    global $admin;
    $client = mkClient(); $doc = mkInvoice($client);
    approve($doc, $admin);
    $collector = mkStaff('Collector A', mkRole('collector', ['menu.followups', 'field_visits.log']));

    [$c, $d] = call(fn () => fc()->store(Request::create('/x', 'POST', ['document_id' => $doc->id, 'next_followup' => now()->toDateString(), 'user_id' => $collector->id])));
    ok($c === 201, 'store: 201');
    ok(Followup::where('document_id', $doc->id)->count() === 1, 'exactly one Followup row after store()');
    ok(CollectionAssignment::where('document_id', $doc->id)->where('assigned_by', $admin->id)->where('status', 'active')->exists(), 'a CollectionAssignment was also created (existing store() behavior), assigned_by = admin');
    $row1 = Followup::where('document_id', $doc->id)->first();
    ok($row1->status === 'pending' && $row1->user_id === $collector->id, 'row1 pending, assigned to collector');

    auth()->login($collector);
    [$c, $d] = call(fn () => fc()->summary(Request::create('/x', 'GET', ['document_ids' => [$doc->id]])));
    ok($c === 200 && $d['data'][0]['followup_id'] === $row1->id && $d['data'][0]['last_outcome'] === null, 'summary before any call: active row is row1, no last_outcome yet');

    [$c, $d] = call(fn () => fc()->logCall(Request::create('/x', 'POST', ['outcome' => 'no_answer', 'notes' => 'Simu haikupokewa']), $row1));
    ok($c === 200 && $d['escalated'] === false, 'logCall: 200, not escalated');
    ok(Followup::where('document_id', $doc->id)->count() === 2, 'logCall spawned a SECOND row — 2 rows total (call-log semantics, not one mutable row)');
    $row1 = $row1->fresh();
    ok($row1->status === 'open' && $row1->outcome === 'no_answer' && $row1->next_followup === null, 'row1: open, outcome recorded, its own next_followup cleared');
    ok($row1->completed_on_time === true && $row1->days_late === 0, 'row1: called same day it was due -> on-time, 0 days late');
    $row2 = Followup::where('document_id', $doc->id)->where('id', '!=', $row1->id)->first();
    ok($row2 && $row2->status === 'pending' && $row2->next_followup->toDateString() === now()->addDays(2)->toDateString(), 'row2: new pending row, next_followup = today+2 (no_answer rule)');

    [$c, $d] = call(fn () => fc()->summary(Request::create('/x', 'GET', ['document_ids' => [$doc->id]])));
    $s = $d['data'][0];
    ok($s['followup_id'] === $row2->id, 'summary now points at row2 (the active one) as the log-call target');
    ok($s['last_outcome'] === 'no_answer' && $s['last_call_date'] !== null, 'summary carries the last CALLED outcome from row1');
    ok($s['next_followup'] === $row2->next_followup->toDateString() && $s['next_followup_overdue'] === false, 'summary next_followup from row2, not overdue');
});

// ---------------------------------------------------------------------------
scenario('column data shape: no follow-up yet vs overdue', function () {
    global $admin;
    $client = mkClient(); $doc = mkInvoice($client);

    [$c, $d] = call(fn () => fc()->summary(Request::create('/x', 'GET', ['document_ids' => [$doc->id]])));
    ok($c === 200 && $d['data'] === [], 'no Followup row at all -> summary omits the document (frontend renders "No follow-up yet")');

    approve($doc, $admin);
    [$c, $d] = call(fn () => fc()->store(Request::create('/x', 'POST', ['document_id' => $doc->id, 'next_followup' => now()->subDay()->toDateString()])));
    ok($c === 201, 'store with a past next_followup succeeds (store() has no after:today rule)');

    [$c, $d] = call(fn () => fc()->summary(Request::create('/x', 'GET', ['document_ids' => [$doc->id]])));
    ok($d['data'][0]['next_followup_overdue'] === true, 'next_followup in the past -> next_followup_overdue true');
});

// ---------------------------------------------------------------------------
scenario('Follow-up button: creates on first use, correctly targets the active row on subsequent logs (no duplicate/orphan rows)', function () {
    global $admin;
    $client = mkClient(); $doc = mkInvoice($client);
    approve($doc, $admin);
    $collector = mkStaff('Collector B', mkRole('collector', ['menu.followups', 'field_visits.log']));
    auth()->login($collector);

    // "Follow-up" button on a fresh invoice: no followup yet -> button auto-creates one (store()).
    [$c, $d] = call(fn () => fc()->store(Request::create('/x', 'POST', ['document_id' => $doc->id, 'next_followup' => now()->toDateString()])));
    ok($c === 201, 'button auto-create: 201');
    $row1id = $d['data']['id'];
    ok(Followup::where('document_id', $doc->id)->count() === 1, '1 row after first button use');

    [$c, $d] = call(fn () => fc()->summary(Request::create('/x', 'GET', ['document_ids' => [$doc->id]])));
    ok($d['data'][0]['followup_id'] === $row1id, 'summary correctly targets row1');

    // Log a call against the row summary() pointed at.
    [$c, $d] = call(fn () => fc()->logCall(Request::create('/x', 'POST', ['outcome' => 'promised', 'notes' => 'Ataliipa', 'promise_date' => now()->addDays(3)->toDateString(), 'promise_amount' => 5000]), Followup::find($row1id)));
    ok($c === 200, 'first logCall: 200');
    ok(Followup::where('document_id', $doc->id)->count() === 2, '2 rows after first call (1 called + 1 auto-scheduled) — reuse, not a fresh store()');

    [$c, $d] = call(fn () => fc()->summary(Request::create('/x', 'GET', ['document_ids' => [$doc->id]])));
    $row2id = $d['data'][0]['followup_id'];
    ok($row2id !== $row1id, 'summary now targets the NEW pending row');

    // Second "Follow-up" click on the SAME invoice: the modal must log against row2, not call store() again.
    [$c, $d] = call(fn () => fc()->logCall(Request::create('/x', 'POST', ['outcome' => 'declined', 'notes' => 'Amekataa']), Followup::find($row2id)));
    ok($c === 200, 'second logCall: 200');
    ok(Followup::where('document_id', $doc->id)->count() === 3, '3 rows total after 2 logged calls (call-log semantics: N calls -> N+1 rows while under the 3-call cap)');
});

// ---------------------------------------------------------------------------
scenario('permission gating matches existing Followups.tsx behavior', function () {
    $noPerm = mkStaff('No Perm', mkRole('no-perms', []));
    ok(permCheck($noPerm, 'menu.followups') === 403, 'user without menu.followups: 403 (cannot see the column/button)');

    $collectorNoLog = mkStaff('Collector No Log', mkRole('collector-no-log', ['menu.followups']));
    ok(permCheck($collectorNoLog, 'menu.followups') === 200, 'has menu.followups: 200 (can see column, create follow-ups)');
    ok(permCheck($collectorNoLog, 'field_visits.log') === 403, 'lacks field_visits.log: 403 on log-call (same gate as Followups.tsx today)');

    global $admin;
    ok(permCheck($admin, 'menu.followups') === 200 && permCheck($admin, 'field_visits.log') === 200, 'admin role: both permissions pass');
});

// ---------------------------------------------------------------------------
scenario('tenant isolation on the summary endpoint', function () {
    global $admin, $tenant;
    $client = mkClient(); $doc = mkInvoice($client);
    approve($doc, $admin);
    call(fn () => fc()->store(Request::create('/x', 'POST', ['document_id' => $doc->id, 'next_followup' => now()->toDateString()])));

    // A synthetic OTHER tenant with its own invoice — fully rolled back, never a real tenant's data.
    // Log out first: BelongsToTenant::creating() would otherwise force tenant_id = admin's tenant.
    auth()->logout();
    $otherTenant = Tenant::create(['name' => 'Followup Isolation Test Tenant ' . uniqid(), 'email' => uniqid() . '@example.test', 'is_active' => true]);
    $otherUser = User::withoutGlobalScopes()->create(['tenant_id' => $otherTenant->id, 'name' => 'Other Admin', 'email' => uniqid() . '@example.test', 'password' => 'x', 'role' => 'user', 'is_active' => true]);
    auth()->login($otherUser);
    $otherClient = Client::create(['tenant_id' => $otherTenant->id, 'name' => 'Other Client', 'phone' => '255700000199', 'email' => uniqid() . '@example.test', 'status' => 'active']);
    $otherDoc = Document::create(['tenant_id' => $otherTenant->id, 'client_id' => $otherClient->id, 'type' => 'invoice', 'document_number' => 'OTH-' . uniqid(), 'date' => now()->toDateString(), 'due_date' => now()->subDays(5)->toDateString(), 'subtotal' => 50000, 'tax_amount' => 0, 'total' => 50000, 'status' => 'overdue']);
    $otherDoc->update(['collection_reviewed_at' => now(), 'collection_reviewed_by' => $otherUser->id]);
    call(fn () => fc()->store(Request::create('/x', 'POST', ['document_id' => $otherDoc->id, 'next_followup' => now()->subDay()->toDateString()])));

    auth()->login($admin);
    [$c, $d] = call(fn () => fc()->summary(Request::create('/x', 'GET', ['document_ids' => [$doc->id, $otherDoc->id]])));
    $ids = array_column($d['data'], 'document_id');
    ok(in_array($doc->id, $ids, true) && !in_array($otherDoc->id, $ids, true), 'summary only returns our tenant\'s document, never the other tenant\'s');

    [$c, $d] = call(fn () => dc()->index(Request::create('/x', 'GET', ['type' => 'invoice', 'followup' => 'overdue'])));
    $ids = array_column($d['data'], 'id');
    ok(!in_array($otherDoc->id, $ids, true), 'followup=overdue quick filter never leaks another tenant\'s invoice');
});

// ---------------------------------------------------------------------------
scenario('modal history: clientHistory shows prior calls for that client', function () {
    global $admin;
    $client = mkClient('History Client'); $doc = mkInvoice($client);
    approve($doc, $admin);
    [, $d1] = call(fn () => fc()->store(Request::create('/x', 'POST', ['document_id' => $doc->id, 'next_followup' => now()->toDateString()])));
    call(fn () => fc()->logCall(Request::create('/x', 'POST', ['outcome' => 'disputed', 'notes' => 'Anasema hakuna huduma aliyopata']), Followup::find($d1['data']['id'])));

    [$c, $d] = call(fn () => fc()->clientHistory($client->id));
    ok($c === 200 && count($d['data']) >= 1, 'clientHistory returns rows');
    $called = collect($d['data'])->firstWhere('outcome', 'disputed');
    ok($called && $called['document_number'] === $doc->document_number && str_contains($called['notes'], 'huduma'), 'history entry has the right invoice + notes staff can review before calling again');
});

// ---------------------------------------------------------------------------
scenario('admin notified when staff logs a call; never self-notified; falls back to documents.approve_collection holders', function () {
    global $admin;
    $collector = mkStaff('Collector C', mkRole('collector', ['menu.followups', 'field_visits.log']));

    // A: admin assigns to collector -> collector logs -> admin notified, collector is not.
    $client = mkClient(); $doc = mkInvoice($client); approve($doc, $admin);
    [, $d] = call(fn () => fc()->store(Request::create('/x', 'POST', ['document_id' => $doc->id, 'next_followup' => now()->toDateString(), 'user_id' => $collector->id])));
    auth()->login($collector);
    call(fn () => fc()->logCall(Request::create('/x', 'POST', ['outcome' => 'no_answer', 'notes' => 'x']), Followup::find($d['data']['id'])));
    ok(Notification::sent($admin, FollowupResponseLoggedNotification::class)->count() === 1, 'A: assigner (admin) notified exactly once');
    ok(Notification::sent($collector, FollowupResponseLoggedNotification::class)->count() === 0, 'A: caller never notifies themselves');

    // B: admin assigns to THEMSELVES and logs their own call -> no self-notification.
    auth()->login($admin);
    $client2 = mkClient(); $doc2 = mkInvoice($client2); approve($doc2, $admin);
    [, $d2] = call(fn () => fc()->store(Request::create('/x', 'POST', ['document_id' => $doc2->id, 'next_followup' => now()->toDateString(), 'user_id' => $admin->id])));
    call(fn () => fc()->logCall(Request::create('/x', 'POST', ['outcome' => 'no_answer', 'notes' => 'x']), Followup::find($d2['data']['id'])));
    ok(Notification::sent($admin, FollowupResponseLoggedNotification::class)->count() === 1, 'B: still just the ONE (from scenario A) — logging your own assigned call sends nothing new');

    // C: no CollectionAssignment at all (e.g. followups:process auto-created) -> fallback to documents.approve_collection holders.
    $client3 = mkClient(); $doc3 = mkInvoice($client3);
    $row3 = Followup::create(['document_id' => $doc3->id, 'client_id' => $client3->id, 'user_id' => $collector->id, 'next_followup' => now()->toDateString(), 'status' => 'pending', 'notes' => 'Auto-created']);
    ok(!CollectionAssignment::where('document_id', $doc3->id)->exists(), 'C: precondition — no CollectionAssignment for this document');
    auth()->login($collector);
    call(fn () => fc()->logCall(Request::create('/x', 'POST', ['outcome' => 'no_answer', 'notes' => 'x']), $row3));
    ok(Notification::sent($admin, FollowupResponseLoggedNotification::class)->count() === 2, 'C: fallback notified admin (holds documents.approve_collection) — one more than before');
});

// ---------------------------------------------------------------------------
scenario('daily reminder digest: one per staff, idempotent, skips staff with nothing due', function () {
    global $admin;
    $collector = mkStaff('Collector D', mkRole('collector', ['menu.followups', 'field_visits.log']));
    $idleCollector = mkStaff('Idle Collector', mkRole('collector', ['menu.followups', 'field_visits.log']));

    $c1 = mkClient(); $d1 = mkInvoice($c1);
    Followup::create(['document_id' => $d1->id, 'client_id' => $c1->id, 'user_id' => $collector->id, 'next_followup' => now()->toDateString(), 'status' => 'pending']);
    $c2 = mkClient(); $d2 = mkInvoice($c2);
    Followup::create(['document_id' => $d2->id, 'client_id' => $c2->id, 'user_id' => $collector->id, 'next_followup' => now()->subDays(2)->toDateString(), 'status' => 'pending']);

    Artisan::call('followups:remind-staff');
    ok(Notification::sent($collector, FollowupReminderDigestNotification::class)->count() === 1, 'collector with 1 due-today + 1 overdue: exactly one digest');
    $sent = Notification::sent($collector, FollowupReminderDigestNotification::class)->first();
    ok($sent->dueTodayCount === 1 && $sent->overdueCount === 1, 'digest carries correct due-today/overdue counts');
    ok(Notification::sent($idleCollector, FollowupReminderDigestNotification::class)->count() === 0, 'staff with nothing due gets nothing');

    // Simulate "already sent today" (what a real, non-faked first run would have persisted) and rerun.
    DB::table('notifications')->insert([
        'id' => (string) \Illuminate\Support\Str::uuid(), 'type' => FollowupReminderDigestNotification::class,
        'notifiable_type' => User::class, 'notifiable_id' => $collector->id, 'data' => '{}',
        'created_at' => now(), 'updated_at' => now(),
    ]);
    Artisan::call('followups:remind-staff');
    ok(Notification::sent($collector, FollowupReminderDigestNotification::class)->count() === 1, 'idempotent: rerunning after a marker exists sends no second digest today');
});

// ---------------------------------------------------------------------------
scenario('on-time / late computed correctly for several call_date vs next_followup combinations', function () {
    global $admin;
    Carbon::setTestNow('2026-06-15 09:00:00');
    $today = Carbon::today();

    $case = function (?Carbon $due) {
        $c = mkClient(); $d = mkInvoice($c);
        return Followup::create(['document_id' => $d->id, 'client_id' => $c->id, 'user_id' => null, 'next_followup' => $due, 'status' => 'pending']);
    };

    $onTimeRow = $case($today);
    call(fn () => fc()->logCall(Request::create('/x', 'POST', ['outcome' => 'no_answer', 'notes' => 'x']), $onTimeRow));
    $onTimeRow = $onTimeRow->fresh();
    ok($onTimeRow->completed_on_time === true && $onTimeRow->days_late === 0, 'due today, called today -> on-time, 0 days late');

    $oneLateRow = $case($today->copy()->subDay());
    call(fn () => fc()->logCall(Request::create('/x', 'POST', ['outcome' => 'no_answer', 'notes' => 'x']), $oneLateRow));
    $oneLateRow = $oneLateRow->fresh();
    ok($oneLateRow->completed_on_time === false && $oneLateRow->days_late === 1, 'due yesterday -> late, 1 day');

    $manyLateRow = $case($today->copy()->subDays(5));
    call(fn () => fc()->logCall(Request::create('/x', 'POST', ['outcome' => 'no_answer', 'notes' => 'x']), $manyLateRow));
    $manyLateRow = $manyLateRow->fresh();
    ok($manyLateRow->completed_on_time === false && $manyLateRow->days_late === 5, 'due 5 days ago -> late, 5 days');

    $noDueRow = $case(null);
    call(fn () => fc()->logCall(Request::create('/x', 'POST', ['outcome' => 'no_answer', 'notes' => 'x']), $noDueRow));
    $noDueRow = $noDueRow->fresh();
    ok($noDueRow->completed_on_time === null && $noDueRow->days_late === null, 'no prior next_followup -> both null (nothing to compare against)');
});

// ---------------------------------------------------------------------------
scenario('staff performance aggregation math', function () {
    global $admin;
    Carbon::setTestNow('2026-06-20 09:00:00');
    $today = Carbon::today();
    $collector = mkStaff('Perf Collector', mkRole('collector', ['menu.followups', 'field_visits.log']));

    $log = function (Carbon $due, string $outcome) use ($collector) {
        $c = mkClient(); $d = mkInvoice($c);
        $row = Followup::create(['document_id' => $d->id, 'client_id' => $c->id, 'user_id' => $collector->id, 'next_followup' => $due, 'status' => 'pending']);
        auth()->login($collector);
        call(fn () => fc()->logCall(Request::create('/x', 'POST', ['outcome' => $outcome, 'notes' => 'x']), $row));
        global $admin; auth()->login($admin);
    };
    $log($today, 'no_answer');                     // on-time
    $log($today->copy(), 'declined');               // on-time
    $log($today->copy()->subDays(4), 'disputed');   // 4 days late

    // One still-overdue, un-actioned follow-up for the same collector.
    $c = mkClient(); $d = mkInvoice($c);
    Followup::create(['document_id' => $d->id, 'client_id' => $c->id, 'user_id' => $collector->id, 'next_followup' => $today->copy()->subDays(2), 'status' => 'pending']);

    [$c2, $res] = call(fn () => fc()->staffPerformance(Request::create('/x', 'GET')));
    $row = collect($res['data'])->firstWhere('user_id', $collector->id);
    ok($c2 === 200 && $row, 'staffPerformance: 200, collector present');
    ok($row['calls_logged'] === 3 && $row['on_time'] === 2 && $row['late'] === 1, 'calls_logged=3, on_time=2, late=1');
    ok(abs($row['on_time_pct'] - 66.7) < 0.05, 'on_time_pct rounds to 66.7');
    ok(abs($row['avg_days_late'] - 4.0) < 0.05, 'avg_days_late = 4.0 (average of the late rows only)');
    ok($row['still_overdue'] === 1, 'still_overdue counts the un-actioned overdue row');
});

// ---------------------------------------------------------------------------
scenario('reassign: happy path — active followup user_id changes, linked CollectionAssignment stays in sync, custom note + audit trail recorded', function () {
    global $admin;
    $client = mkClient(); $doc = mkInvoice($client);
    approve($doc, $admin);
    $collectorA = mkStaff('Reassign A', mkRole('collector', ['menu.followups', 'field_visits.log']));
    $collectorB = mkStaff('Reassign B', mkRole('collector', ['menu.followups', 'field_visits.log']));

    [$c, $d] = call(fn () => fc()->store(Request::create('/x', 'POST', ['document_id' => $doc->id, 'next_followup' => now()->addDay()->toDateString(), 'user_id' => $collectorA->id])));
    ok($c === 201, 'store: 201');
    $followup = Followup::find($d['data']['id']);
    $assignment = CollectionAssignment::where('document_id', $doc->id)->where('status', 'active')->first();
    ok($assignment && $assignment->user_id === $collectorA->id, 'precondition: CollectionAssignment starts with collector A');

    [$c, $d] = call(fn () => fc()->reassign(Request::create('/x', 'PATCH', ['user_id' => $collectorB->id, 'notes' => 'Call after 3pm, speaks Swahili only']), $followup));
    ok($c === 200, 'reassign: 200');
    $followup = $followup->fresh();
    ok($followup->user_id === $collectorB->id, 'active followup row now assigned to collector B');
    ok(str_starts_with($followup->notes, 'Call after 3pm, speaks Swahili only'), 'custom note kept as the primary, readable text');
    ok(str_contains($followup->notes, 'Reassigned from Reassign A to Reassign B by'), 'audit trail (from/to/by) appended');
    $assignment = $assignment->fresh();
    ok($assignment->user_id === $collectorB->id, 'linked CollectionAssignment user_id kept in sync');
    ok(CollectionAssignment::where('document_id', $doc->id)->count() === 1, 'no duplicate CollectionAssignment created');
});

// ---------------------------------------------------------------------------
scenario('reassign: no-op refusal when the new user is already the current assignee', function () {
    global $admin;
    $client = mkClient(); $doc = mkInvoice($client);
    approve($doc, $admin);
    $collector = mkStaff('Noop Collector', mkRole('collector', ['menu.followups', 'field_visits.log']));

    [, $d] = call(fn () => fc()->store(Request::create('/x', 'POST', ['document_id' => $doc->id, 'next_followup' => now()->addDay()->toDateString(), 'user_id' => $collector->id])));
    $followup = Followup::find($d['data']['id']);

    [$c, $d] = call(fn () => fc()->reassign(Request::create('/x', 'PATCH', ['user_id' => $collector->id]), $followup));
    ok($c === 422 && str_contains($d['message'], 'already assigned'), 'reassigning to the same current assignee: 422 no-op');
    ok($followup->fresh()->user_id === $collector->id, 'nothing changed');
});

// ---------------------------------------------------------------------------
scenario('reassign: gated by its own admin-only followups.reassign permission, not the broader menu.followups bulkAssign uses or documents.approve_collection (which nearly every role holds)', function () {
    global $admin;
    $collectorNoApprove = mkStaff('No Approve', mkRole('collector-no-approve', ['menu.followups', 'field_visits.log', 'documents.approve_collection']));
    ok(permCheck($collectorNoApprove, 'followups.reassign') === 403, 'ordinary collector (has menu.followups + documents.approve_collection, lacks followups.reassign): 403');
    ok(permCheck($admin, 'followups.reassign') === 200, 'admin (has followups.reassign): 200');
});

// ---------------------------------------------------------------------------
scenario('reassign: tenant isolation — cannot resolve another tenant\'s followup (404)', function () {
    global $admin;
    auth()->logout();
    $otherTenant = Tenant::create(['name' => 'Followup Reassign Isolation Tenant ' . uniqid(), 'email' => uniqid() . '@example.test', 'is_active' => true]);
    $otherUser = User::withoutGlobalScopes()->create(['tenant_id' => $otherTenant->id, 'name' => 'Other Admin', 'email' => uniqid() . '@example.test', 'password' => 'x', 'role' => 'user', 'is_active' => true]);
    auth()->login($otherUser);
    $otherClient = Client::create(['tenant_id' => $otherTenant->id, 'name' => 'Other Client', 'phone' => '255700000299', 'email' => uniqid() . '@example.test', 'status' => 'active']);
    $otherDoc = Document::create(['tenant_id' => $otherTenant->id, 'client_id' => $otherClient->id, 'type' => 'invoice', 'document_number' => 'OTH2-' . uniqid(), 'date' => now()->toDateString(), 'due_date' => now()->subDays(5)->toDateString(), 'subtotal' => 50000, 'tax_amount' => 0, 'total' => 50000, 'status' => 'overdue']);
    $otherDoc->update(['collection_reviewed_at' => now(), 'collection_reviewed_by' => $otherUser->id]);
    $otherFollowup = Followup::create(['tenant_id' => $otherTenant->id, 'document_id' => $otherDoc->id, 'client_id' => $otherClient->id, 'user_id' => $otherUser->id, 'next_followup' => now()->toDateString(), 'status' => 'pending']);

    auth()->login($admin);
    [$c, $d] = call(fn () => fc()->reassign(Request::create('/x', 'PATCH', ['user_id' => $admin->id]), Followup::findOrFail($otherFollowup->id)));
    ok($c === 404, 'a different tenant\'s followup id cannot be resolved/reassigned (404)');
});

// ---------------------------------------------------------------------------
scenario('reassign: notifies the new assignee and the previous assignee; never self-notifies', function () {
    global $admin;
    $client = mkClient(); $doc = mkInvoice($client);
    approve($doc, $admin);
    $collectorA = mkStaff('Notify A', mkRole('collector', ['menu.followups', 'field_visits.log']));
    $collectorB = mkStaff('Notify B', mkRole('collector', ['menu.followups', 'field_visits.log']));

    [, $d] = call(fn () => fc()->store(Request::create('/x', 'POST', ['document_id' => $doc->id, 'next_followup' => now()->addDay()->toDateString(), 'user_id' => $collectorA->id])));
    $followup = Followup::find($d['data']['id']);

    // A: admin reassigns from collector A to collector B.
    call(fn () => fc()->reassign(Request::create('/x', 'PATCH', ['user_id' => $collectorB->id]), $followup));
    ok(Notification::sent($collectorB, FollowupAssignedNotification::class)->count() === 1, 'A: new assignee (B) gets FollowupAssignedNotification');
    ok(Notification::sent($collectorA, FollowupUnassignedNotification::class)->count() === 1, 'A: previous assignee (A) gets FollowupUnassignedNotification');
    ok(Notification::sent($collectorB, FollowupUnassignedNotification::class)->count() === 0, 'A: new assignee never gets the unassigned notification');
    // Collector A already got ONE FollowupAssignedNotification from the earlier store() call above (the
    // original assignment) — the reassignment away from them must not add a second one.
    ok(Notification::sent($collectorA, FollowupAssignedNotification::class)->count() === 1, 'A: previous assignee gets no NEW assigned notification from being reassigned away');

    // B: admin reassigns the same invoice to THEMSELVES -> no self-notification; collector B (just replaced) is notified.
    call(fn () => fc()->reassign(Request::create('/x', 'PATCH', ['user_id' => $admin->id]), $followup->fresh()));
    ok(Notification::sent($admin, FollowupAssignedNotification::class)->count() === 0, 'B: admin reassigning to themselves: no self-notification');
    ok(Notification::sent($collectorB, FollowupUnassignedNotification::class)->count() === 1, 'B: collector B (just replaced) notified of unassignment');
});

// ---------------------------------------------------------------------------
scenario('reassign: refused once the invoice is settled/cancelled (terminal state)', function () {
    global $admin;
    $client = mkClient(); $doc = mkInvoice($client);
    approve($doc, $admin);
    $collectorA = mkStaff('Terminal A', mkRole('collector', ['menu.followups', 'field_visits.log']));
    $collectorB = mkStaff('Terminal B', mkRole('collector', ['menu.followups', 'field_visits.log']));
    [, $d] = call(fn () => fc()->store(Request::create('/x', 'POST', ['document_id' => $doc->id, 'next_followup' => now()->addDay()->toDateString(), 'user_id' => $collectorA->id])));
    $followup = Followup::find($d['data']['id']);

    $doc->update(['status' => 'paid']);
    [$c, $d] = call(fn () => fc()->reassign(Request::create('/x', 'PATCH', ['user_id' => $collectorB->id]), $followup->fresh()));
    ok($c === 422 && str_contains($d['message'], 'settled or cancelled'), 'paid invoice: reassign refused, 422');

    $doc->update(['status' => 'cancelled']);
    [$c, $d] = call(fn () => fc()->reassign(Request::create('/x', 'PATCH', ['user_id' => $collectorB->id]), $followup->fresh()));
    ok($c === 422, 'cancelled invoice: reassign refused, 422');
    ok($followup->fresh()->user_id === $collectorA->id, 'nothing changed by either refused attempt');
});

// ---------------------------------------------------------------------------
scenario('client history on MyCollections: a staff member sees their assigned client\'s prior follow-up history and notes; tenant-isolated', function () {
    global $admin;
    $client = mkClient('MyCollections History Client'); $doc = mkInvoice($client);
    approve($doc, $admin);
    $collector = mkStaff('History Collector', mkRole('collector', ['menu.followups', 'field_visits.log']));

    [, $d] = call(fn () => fc()->store(Request::create('/x', 'POST', ['document_id' => $doc->id, 'next_followup' => now()->toDateString(), 'user_id' => $collector->id])));
    auth()->login($collector);
    call(fn () => fc()->logCall(Request::create('/x', 'POST', ['outcome' => 'promised', 'notes' => 'Atalipa Ijumaa', 'promise_date' => now()->addDays(2)->toDateString(), 'promise_amount' => 20000]), Followup::find($d['data']['id'])));

    // This is the exact call MyCollections.tsx's LogCallModal now makes automatically (via ClientFollowupHistory) before the staff member dials.
    [$c, $d2] = call(fn () => fc()->clientHistory($client->id));
    ok($c === 200, 'clientHistory: 200 for the assigned collector');
    $entry = collect($d2['data'])->firstWhere('outcome', 'promised');
    ok($entry && $entry['document_number'] === $doc->document_number && str_contains($entry['notes'], 'Ijumaa'), 'collector sees the call they just logged, correct invoice + notes');

    // Tenant isolation: a client id belonging to another tenant returns nothing (same BelongsToTenant scope clientHistory has always relied on).
    auth()->logout();
    $otherTenant = Tenant::create(['name' => 'Client History Isolation Tenant ' . uniqid(), 'email' => uniqid() . '@example.test', 'is_active' => true]);
    $otherUser = User::withoutGlobalScopes()->create(['tenant_id' => $otherTenant->id, 'name' => 'Other Admin', 'email' => uniqid() . '@example.test', 'password' => 'x', 'role' => 'user', 'is_active' => true]);
    auth()->login($otherUser);
    $otherClient = Client::create(['tenant_id' => $otherTenant->id, 'name' => 'Other Client', 'phone' => '255700000399', 'email' => uniqid() . '@example.test', 'status' => 'active']);
    $otherDoc = Document::create(['tenant_id' => $otherTenant->id, 'client_id' => $otherClient->id, 'type' => 'invoice', 'document_number' => 'OTH3-' . uniqid(), 'date' => now()->toDateString(), 'due_date' => now()->subDays(5)->toDateString(), 'subtotal' => 30000, 'tax_amount' => 0, 'total' => 30000, 'status' => 'overdue']);
    Followup::create(['tenant_id' => $otherTenant->id, 'document_id' => $otherDoc->id, 'client_id' => $otherClient->id, 'user_id' => $otherUser->id, 'next_followup' => now()->toDateString(), 'status' => 'pending']);

    auth()->login($collector);
    [$c, $d3] = call(fn () => fc()->clientHistory($otherClient->id));
    ok($c === 200 && $d3['data'] === [], 'a collector in one tenant sees no rows for a client id belonging to another tenant');
});

echo $fail ? "FAILED $fail\n" : "ALL PASSED\n";
exit($fail ? 1 : 0);

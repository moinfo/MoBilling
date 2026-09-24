<?php
// php tests/Manual/run_linode_power.php  (live DB, rolled back, Linode fully faked - NO real API calls)
require __DIR__ . '/../../vendor/autoload.php';
$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Http\Controllers\LinodeController;
use App\Http\Middleware\CheckPermission;
use App\Models\{LinodeAccount, LinodeAuditLog, LinodeResource, Tenant, User};
use App\Services\Linode\LinodeService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\{DB, Http};

const TOKEN = 'lin_SECRET_TOKEN_abcdefghijklmnopqrstuvwxyz1234';
LinodeService::$sleepOnRateLimit = false;
$fail = 0;
function ok($c, $m) { global $fail; if (!$c) { $fail++; echo "FAIL $m\n"; } else echo "PASS $m\n"; }
function fk($x) { Http::swap(new \Illuminate\Http\Client\Factory()); Http::preventStrayRequests(); Http::fake($x); }
function j($r) { return $r->getData(true); }
function pw($res, $d) { app()->instance('request', Request::create('/x', 'POST', $d)); return app(LinodeController::class)->power(app('request'), $res); }
function posts() { return Http::recorded(fn ($r) => $r->method() === 'POST')->count(); }

DB::beginTransaction();
try {
    $tenantA = Tenant::withoutGlobalScopes()->where('name', 'MoBilling Test Co')->firstOrFail();
    $userA = User::withoutGlobalScopes()->where('tenant_id', $tenantA->id)->firstOrFail();
    auth()->login($userA);

    $acct = new LinodeAccount(['label' => 'T', 'token' => TOKEN, 'token_hint' => '1234', 'status' => 'active']);
    $acct->tenant_id = $tenantA->id; $acct->save();
    $mk = fn ($id, $label) => LinodeResource::create(['tenant_id' => $tenantA->id, 'linode_account_id' => $acct->id, 'type' => 'instance', 'remote_id' => $id, 'label' => $label, 'status' => 'running', 'ipv4' => ['203.0.113.' . ($id % 200)]]);
    $s1 = $mk('9001', 'srv-one'); $s2 = $mk('9002', 'srv-two');
    $get = fn ($id, $st) => ["api.linode.com/v4/linode/instances/$id" => Http::response(['id' => $id, 'status' => $st])];
    $post = fn ($id, $a, $code = 200, $body = []) => ["api.linode.com/v4/linode/instances/$id/$a" => Http::response($body, $code)];

    // running -> reboot ok, exactly one POST to expected URL
    fk($get(9001, 'running') + $post(9001, 'reboot'));
    $r = pw($s1, ['action' => 'reboot', 'confirm_label' => 'srv-one']);
    ok($r->getStatusCode() === 200 && $s1->fresh()->status === 'rebooting', 'running -> reboot ok, status optimistic rebooting');
    ok(posts() === 1 && Http::recorded(fn ($q) => $q->method() === 'POST' && $q->url() === 'https://api.linode.com/v4/linode/instances/9001/reboot')->count() === 1, 'exactly one POST to /reboot');
    $s1->update(['status' => 'running']);

    // wrong / missing label
    fk([]);
    ok(pw($s1, ['action' => 'reboot', 'confirm_label' => 'SRV-ONE'])->getStatusCode() === 422, 'case-different label refused');
    ok(pw($s1, ['action' => 'shutdown'])->getStatusCode() === 422, 'missing label refused (shutdown)');
    ok(pw($s1, ['action' => 'boot'])->getStatusCode() === 422, 'boot without confirm refused');
    ok(Http::recorded()->count() === 0, 'no HTTP made on refusals');

    // offline: reboot refused, boot ok
    fk($get(9001, 'offline') + $post(9001, 'boot'));
    $r = pw($s1, ['action' => 'reboot', 'confirm_label' => 'srv-one']);
    ok($r->getStatusCode() === 409 && posts() === 0, 'offline -> reboot refused, no POST');
    $r = pw($s1, ['action' => 'boot', 'confirm' => true]);
    ok($r->getStatusCode() === 200 && posts() === 1 && $s1->fresh()->status === 'booting', 'offline -> boot ok (one POST)');
    $s1->update(['status' => 'offline']);

    // running -> boot refused; shutdown ok
    fk($get(9002, 'running') + $post(9002, 'shutdown'));
    ok(pw($s2, ['action' => 'boot', 'confirm' => true])->getStatusCode() === 409, 'running -> boot refused');
    ok(pw($s2, ['action' => 'shutdown', 'confirm_label' => 'srv-two'])->getStatusCode() === 200 && $s2->fresh()->status === 'shutting_down', 'running -> shutdown ok');
    $s2->update(['status' => 'running']);

    // busy
    foreach (['rebooting', 'booting', 'shutting_down', 'migrating', 'provisioning'] as $busy) {
        fk($get(9002, $busy) + $post(9002, 'reboot'));
        $r = pw($s2, ['action' => 'reboot', 'confirm_label' => 'srv-two']);
        ok($r->getStatusCode() === 409 && str_contains(j($r)['message'], 'busy') && posts() === 0, "busy ($busy) refused");
    }

    // Linode 403 -> scope message; Linode 400 busy -> friendly
    fk($get(9002, 'running') + $post(9002, 'reboot', 403, ['errors' => [['reason' => 'Unauthorized']]]));
    $r = pw($s2, ['action' => 'reboot', 'confirm_label' => 'srv-two']);
    ok($r->getStatusCode() === 422 && str_contains(j($r)['message'], 'linodes: read/write') && $s2->fresh()->status === 'running', '403 from Linode -> scope message, status unchanged');
    fk($get(9002, 'running') + $post(9002, 'reboot', 400, ['errors' => [['reason' => 'Linode busy.']]]));
    $r = pw($s2, ['action' => 'reboot', 'confirm_label' => 'srv-two']);
    ok($r->getStatusCode() === 422 && str_contains(j($r)['message'], 'busy'), '400 busy from Linode -> friendly message');

    // single-status refresh
    fk($get(9002, 'offline'));
    $r = app(LinodeController::class)->serverStatus($s2);
    ok(j($r)['data']['status'] === 'offline' && $s2->fresh()->status === 'offline', 'single-server status refresh');
    $s2->update(['status' => 'running']);

    // audit
    $rows = LinodeAuditLog::whereIn('action', ['server.power', 'server.power_refused'])->get();
    ok($rows->where('action', 'server.power')->where('response_status', 200)->count() === 3, 'success audits written (reboot, boot, shutdown)');
    ok($rows->where('action', 'server.power')->where('response_status', 403)->count() === 1, 'failed (403) audit written');
    ok($rows->where('action', 'server.power_refused')->count() >= 8 && $rows->every(fn ($x) => $x->user_id === $userA->id), 'refusal audits written with user');
    ok(!str_contains(json_encode($rows->toArray()), 'SECRET') && !str_contains(json_encode($rows->toArray()), TOKEN), 'no token in audit rows');

    // rate limits: per server 5/hour (executed actions so far on s2: shutdown, 403, 400 = 3; s1: 2)
    fk($get(9001, 'running') + $post(9001, 'reboot'));
    LinodeAuditLog::where('action', 'server.power')->delete();
    for ($i = 0; $i < 5; $i++) { $s1->update(['status' => 'running']); pw($s1, ['action' => 'reboot', 'confirm_label' => 'srv-one']); }
    $s1->update(['status' => 'running']);
    $r = pw($s1, ['action' => 'reboot', 'confirm_label' => 'srv-one']);
    ok($r->getStatusCode() === 429 && posts() === 5, '6th action on one server in an hour -> 429, no extra POST');
    LinodeAuditLog::where('action', 'server.power')->delete();
    $bulk = [];
    for ($i = 0; $i < 20; $i++) LinodeAuditLog::create(['tenant_id' => $tenantA->id, 'user_id' => $userA->id, 'linode_account_id' => $acct->id, 'action' => 'server.power', 'target' => "x$i #$i", 'response_status' => 200]);
    fk($get(9002, 'running') + $post(9002, 'reboot'));
    $r = pw($s2, ['action' => 'reboot', 'confirm_label' => 'srv-two']);
    ok($r->getStatusCode() === 429 && posts() === 0, '21st action for tenant in an hour -> 429');

    // permission
    $has = fn ($u) => $u->hasAnyPermission(['linode.power']);
    $noPerm = User::withoutGlobalScopes()->whereNotNull('role_id')->limit(400)->get()->first(fn ($u) => !$u->isSuperAdmin() && !$has($u));
    if ($noPerm) {
        $rq = Request::create('/x'); $rq->setUserResolver(fn () => $noPerm);
        ok((new CheckPermission())->handle($rq, fn () => response('ok'), 'linode.power')->getStatusCode() === 403, 'user without linode.power gets 403');
    } else echo "SKIP no user without linode.power\n";
    $adm = User::withoutGlobalScopes()->whereHas('role', fn ($q) => $q->where('name', 'admin'))->get()->first(fn ($u) => !$u->isSuperAdmin() && $has($u));
    if ($adm) {
        $rq = Request::create('/x'); $rq->setUserResolver(fn () => $adm);
        ok((new CheckPermission())->handle($rq, fn () => response('ok'), 'linode.power')->getStatusCode() === 200, 'admin role passes linode.power');
    } else echo "SKIP no non-super admin found\n";
    ok(DB::table('permissions')->where('name', 'linode.power')->exists(), 'permission seeded');

    // tenant isolation: tenant B user cannot resolve tenant A server (route binding uses the scoped model)
    $other = User::withoutGlobalScopes()->where('tenant_id', '!=', $tenantA->id)->whereNotNull('tenant_id')->first();
    if ($other) {
        auth()->login($other);
        ok(LinodeResource::find($s1->id) === null, 'tenant B cannot resolve tenant A server (-> 404)');
        auth()->login($userA);
    } else echo "SKIP no second tenant user\n";
} catch (\Throwable $e) {
    $fail++; echo 'FAIL exception ' . $e->getMessage() . ' @' . $e->getLine() . "\n";
}
DB::rollBack();
echo $fail ? "$fail FAILED\n" : "ALL PASSED\n";
exit($fail ? 1 : 0);

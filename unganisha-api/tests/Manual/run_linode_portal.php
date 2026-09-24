<?php
// php tests/Manual/run_linode_portal.php  (live DB rolled back; Linode fully faked, notifications faked - NO real calls)
require __DIR__ . '/../../vendor/autoload.php';
$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Http\Controllers\LinodeDomainRequestController;
use App\Http\Controllers\Portal\PortalLinodeController;
use App\Models\{Client, ClientSubscription, ClientUser, LinodeAccount, LinodeAuditLog, LinodeDomainRequest, LinodeResource, ProductService, Tenant, Ticket, User};
use App\Notifications\LinodeDomainRequestNotification;
use App\Services\Linode\LinodeService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\{DB, Http, Notification};

const TOKEN = 'lin_SECRET_TOKEN_abcdefghijklmnopqrstuvwxyz1234';
LinodeService::$sleepOnRateLimit = false;
LinodeService::$paginatedGapMs = 0;
$fail = 0;
function ok($c, $m) { global $fail; if (!$c) { $fail++; echo "FAIL $m\n"; } else echo "PASS $m\n"; }
function fk($x) { Http::swap(new \Illuminate\Http\Client\Factory()); Http::preventStrayRequests(); Http::fake($x); }
function j($r) { return $r->getData(true); }
function posts() { return Http::recorded(fn ($r) => $r->method() === 'POST')->count(); }
function asPortal(ClientUser $u) { auth()->setUser($u); }
function call(ClientUser $u, string $m, string $srvId, array $d = []) {
    asPortal($u);
    $rq = Request::create('/x', 'POST', $d); $rq->setUserResolver(fn () => $u); app()->instance('request', $rq);
    try { return (in_array($m, ['index']) ? app(PortalLinodeController::class)->$m($rq) : app(PortalLinodeController::class)->$m($rq, $srvId)); }
    catch (\Symfony\Component\HttpKernel\Exception\HttpException $e) { return response()->json(['message' => $e->getMessage()], $e->getStatusCode()); }
    catch (\Illuminate\Validation\ValidationException $e) { return response()->json(['message' => $e->getMessage()], 422); }
}
function staffCall(User $s, string $m, $row, array $d = []) {
    auth()->setUser($s);
    $rq = Request::create('/x', 'POST', $d); $rq->setUserResolver(fn () => $s); app()->instance('request', $rq);
    return app(LinodeDomainRequestController::class)->$m($rq, $row);
}

Notification::fake();
DB::beginTransaction();
try {
    $tenantA = Tenant::withoutGlobalScopes()->where('name', 'MoBilling Test Co')->firstOrFail();
    $staffA = User::withoutGlobalScopes()->where('tenant_id', $tenantA->id)->firstOrFail();
    auth()->setUser($staffA);

    $acct = new LinodeAccount(['label' => 'T', 'token' => TOKEN, 'token_hint' => '1234', 'status' => 'active', 'soa_email' => 'soa@example.test']);
    $acct->tenant_id = $tenantA->id; $acct->save();
    $mkSrv = fn ($id, $label, $ip, $client, $sub) => LinodeResource::create(['tenant_id' => $tenantA->id, 'linode_account_id' => $acct->id, 'type' => 'instance', 'remote_id' => $id, 'label' => $label, 'status' => 'running', 'region' => 'eu-central', 'ipv4' => [$ip], 'client_id' => $client?->id, 'client_subscription_id' => $sub?->id]);
    $cA = Client::create(['name' => 'Portal A TEST', 'phone' => '255700000201', 'email' => 'a@example.test', 'status' => 'active']);
    $cB = Client::create(['name' => 'Portal B TEST', 'phone' => '255700000202', 'email' => 'b@example.test', 'status' => 'active']);
    $prod = ProductService::create(['type' => 'service', 'name' => 'Linode Server TEST', 'price' => 1000, 'tax_percent' => 0, 'unit' => 'pcs', 'category' => 'Linode Servers', 'billing_cycle' => 'yearly', 'provisioning_type' => 'linode', 'portal_visible' => false, 'is_active' => true]);
    $mkSub = fn ($c) => ClientSubscription::create(['client_id' => $c->id, 'product_service_id' => $prod->id, 'label' => 'srv', 'quantity' => 1, 'start_date' => '2026-01-01', 'expire_date' => '2027-01-01', 'status' => 'active']);
    $subA = $mkSub($cA); $subB = $mkSub($cB);
    $sA = $mkSrv('7001', 'a-server', '203.0.113.71', $cA, $subA);
    $sB = $mkSrv('7002', 'b-server', '203.0.113.72', $cB, $subB);
    $sUnlinked = $mkSrv('7003', 'free-server', '203.0.113.73', $cA, null);
    $mkUser = fn ($c, $role, $email) => ClientUser::create(['client_id' => $c->id, 'tenant_id' => $tenantA->id, 'name' => 'U ' . $email, 'email' => $email, 'password' => 'x-Secret-123', 'role' => $role, 'is_active' => true]);
    $uA = $mkUser($cA, 'admin', 'ua@example.test'); $uAv = $mkUser($cA, 'viewer', 'uav@example.test'); $uB = $mkUser($cB, 'admin', 'ub@example.test');
    $get = fn ($id, $st) => ["api.linode.com/v4/linode/instances/$id" => Http::response(['id' => $id, 'status' => $st])];
    $post = fn ($id, $a, $code = 200) => ["api.linode.com/v4/linode/instances/$id/$a" => Http::response([], $code)];

    // ---- reboot
    fk($get(7001, 'running') + $post(7001, 'reboot'));
    $r = call($uA, 'reboot', $sA->id, ['confirm_label' => 'a-server']);
    ok($r->getStatusCode() === 200 && $sA->fresh()->status === 'rebooting', 'own server reboot ok, status rebooting');
    ok(posts() === 1 && Http::recorded(fn ($q) => $q->method() === 'POST' && $q->url() === 'https://api.linode.com/v4/linode/instances/7001/reboot')->count() === 1, 'exactly one POST /reboot');
    $body = json_encode(j($r));
    ok(!str_contains($body, TOKEN) && !str_contains($body, '7001') && !str_contains($body, 'remote_id') && !str_contains($body, 'linode_account'), 'reboot response has no token / remote id / account');
    $a1 = LinodeAuditLog::where('action', 'portal.server_reboot')->latest('created_at')->first();
    ok($a1 && $a1->user_id === $uA->id && $a1->request['client_id'] === $cA->id && $a1->request['portal_user_id'] === $uA->id && $a1->response_status === 200, 'audited with client + portal user');
    $sA->update(['status' => 'running']);

    // other client / unlinked / unknown -> 404, no HTTP
    fk([]);
    ok(call($uA, 'reboot', $sB->id, ['confirm_label' => 'b-server'])->getStatusCode() === 404, "other client's server -> 404");
    ok(call($uB, 'reboot', $sA->id, ['confirm_label' => 'a-server'])->getStatusCode() === 404, 'reverse direction -> 404');
    ok(call($uA, 'reboot', $sUnlinked->id, ['confirm_label' => 'free-server'])->getStatusCode() === 404, 'server without linked subscription -> 404');
    ok(call($uA, 'reboot', 'nope', ['confirm_label' => 'x'])->getStatusCode() === 404, 'unknown id -> 404');
    ok(call($uAv, 'reboot', $sA->id, ['confirm_label' => 'a-server'])->getStatusCode() === 403, 'viewer role -> 403');
    ok(call($uAv, 'requestDomain', $sA->id, ['domain' => 'viewer.com'])->getStatusCode() === 403, 'viewer cannot request domain');
    // wrong confirm
    ok(call($uA, 'reboot', $sA->id, ['confirm_label' => 'A-SERVER'])->getStatusCode() === 422, 'wrong-case confirm name refused');
    ok(call($uA, 'reboot', $sA->id, [])->getStatusCode() === 422, 'missing confirm refused');
    ok(Http::recorded()->count() === 0, 'no HTTP on refusals');
    // inactive subscription -> 404
    $subA->update(['status' => 'cancelled']);
    ok(call($uA, 'reboot', $sA->id, ['confirm_label' => 'a-server'])->getStatusCode() === 404, 'cancelled subscription -> 404');
    $subA->update(['status' => 'active']);
    // inactive account / gone
    $acct->update(['status' => 'invalid']);
    ok(call($uA, 'reboot', $sA->id, ['confirm_label' => 'a-server'])->getStatusCode() === 422, 'inactive Linode account refused');
    $acct->update(['status' => 'active']);
    $sA->update(['status' => 'gone']);
    ok(call($uA, 'reboot', $sA->id, ['confirm_label' => 'a-server'])->getStatusCode() === 422, 'gone server refused');
    $sA->update(['status' => 'running']);
    // non-running / busy
    foreach (['offline', 'rebooting', 'booting', 'migrating'] as $st) {
        fk($get(7001, $st) + $post(7001, 'reboot'));
        $r = call($uA, 'reboot', $sA->id, ['confirm_label' => 'a-server']);
        ok($r->getStatusCode() === 409 && posts() === 0, "live status $st -> refused, no POST");
    }
    // Linode 403 -> generic message, no scope hint
    LinodeAuditLog::where('action', 'portal.server_reboot')->delete();
    fk($get(7001, 'running') + $post(7001, 'reboot', 403));
    $r = call($uA, 'reboot', $sA->id, ['confirm_label' => 'a-server']);
    ok($r->getStatusCode() === 422 && !str_contains(j($r)['message'], 'token') && $sA->fresh()->status === 'running', 'Linode 403 -> generic client message, status unchanged');

    // rate limits: 2 per server per hour
    LinodeAuditLog::where('action', 'portal.server_reboot')->delete();
    fk($get(7001, 'running') + $post(7001, 'reboot'));
    for ($i = 0; $i < 2; $i++) { $sA->update(['status' => 'running']); call($uA, 'reboot', $sA->id, ['confirm_label' => 'a-server']); }
    $sA->update(['status' => 'running']);
    $r = call($uA, 'reboot', $sA->id, ['confirm_label' => 'a-server']);
    ok($r->getStatusCode() === 429 && posts() === 2, '3rd reboot of a server in an hour -> 429, no extra POST');
    // 5 per client per day (spread across hours so the hourly limit does not fire)
    LinodeAuditLog::where('action', 'portal.server_reboot')->delete();
    for ($i = 0; $i < 5; $i++) LinodeAuditLog::create(['tenant_id' => $tenantA->id, 'user_id' => $uA->id, 'linode_account_id' => $acct->id, 'action' => 'portal.server_reboot', 'target' => "old$i #$i", 'request' => ['client_id' => $cA->id], 'response_status' => 200]);
    LinodeAuditLog::where('action', 'portal.server_reboot')->update(['created_at' => now()->subHours(5)]);
    fk($get(7001, 'running') + $post(7001, 'reboot') + $get(7002, 'running') + $post(7002, 'reboot'));
    $r = call($uA, 'reboot', $sA->id, ['confirm_label' => 'a-server']);
    ok($r->getStatusCode() === 429 && posts() === 0, '6th reboot for one client in a day -> 429');
    ok(call($uB, 'reboot', $sB->id, ['confirm_label' => 'b-server'])->getStatusCode() === 200 && posts() === 1, "client A's daily limit does not block client B");

    // ---- domains list (read-only, from mapping data)
    $dom = fn ($label, $client, $ips, $rid) => LinodeResource::create(['tenant_id' => $tenantA->id, 'linode_account_id' => $acct->id, 'type' => 'domain', 'remote_id' => $rid, 'label' => $label, 'status' => 'active', 'client_id' => $client?->id,
        'meta' => ['dns' => ['apex_ips' => $ips, 'www_ips' => $ips, 'fetched_at' => now()->toIso8601String()]]]);
    $dom('mine.co.tz', $cA, ['203.0.113.71'], '501');
    $dom('otherclient.co.tz', $cB, ['203.0.113.71'], '502');      // points to A's server but belongs to B
    $dom('elsewhere.co.tz', $cA, ['203.0.113.72'], '503');        // A's but points to B's server
    $dom('unmapped.co.tz', null, ['203.0.113.71'], '504');
    fk([]);
    $r = call($uA, 'show', $sA->id);
    $d = j($r)['data'];
    ok($r->getStatusCode() === 200 && collect($d['domains'])->pluck('name')->all() === ['mine.co.tz'], 'domains list = own client domains pointing at this server only');
    ok($d['server']['name'] === 'a-server' && $d['server']['ip'] === '203.0.113.71', 'server facts present');
    ok(!str_contains(json_encode(j($r)), TOKEN) && !str_contains(json_encode(j($r)), 'remote_id') && Http::recorded()->count() === 0, 'show: no secrets, no Linode call');
    ok(call($uA, 'show', $sB->id)->getStatusCode() === 404, 'show other client server -> 404');
    $list = j(call($uA, 'index', ''))['data'];
    ok(collect($list)->pluck('id')->contains($sA->id) && !collect($list)->pluck('id')->contains($sB->id), 'index lists only own servers');
    ok(!str_contains(json_encode($list), TOKEN) && !str_contains(json_encode($list), 'remote_id'), 'index: no secrets');

    // ---- client adds a domain directly (no approval)
    $fakeAdd = fn ($id, $dom, $ip) => [
        'api.linode.com/v4/domains' => Http::response(['id' => $id, 'domain' => $dom, 'status' => 'active', 'soa_email' => 'soa@example.test', 'ttl_sec' => 0], 200),
        "api.linode.com/v4/domains/$id/records*" => Http::sequence()
            ->push(['data' => [], 'page' => 1, 'pages' => 1, 'results' => 0])->push(['id' => 1, 'type' => 'A', 'name' => '', 'target' => $ip, 'ttl_sec' => 0])
            ->push(['data' => [['id' => 1, 'type' => 'A', 'name' => '', 'target' => $ip, 'ttl_sec' => 0]], 'page' => 1, 'pages' => 1, 'results' => 1])->push(['id' => 2, 'type' => 'A', 'name' => 'www', 'target' => $ip, 'ttl_sec' => 0]),
    ];
    fk($fakeAdd(9200, 'direct-site.co.tz', '203.0.113.71'));
    $r = call($uA, 'requestDomain', $sA->id, ['domain' => 'Direct-Site.co.tz']);
    $dres = LinodeResource::where('type', 'domain')->where('label', 'direct-site.co.tz')->first();
    ok($r->getStatusCode() === 201 && $dres && $dres->client_id === $cA->id, 'client adds domain directly: created in Linode (faked) and mapped to the client');
    ok(Http::recorded(fn ($q) => $q->method() === 'POST' && $q->url() === 'https://api.linode.com/v4/domains')->count() === 1
       && Http::recorded(fn ($q) => !in_array($q->method(), ['GET', 'POST']))->count() === 0, 'one domain POST, no DELETE/other verbs');
    ok(LinodeDomainRequest::where('domain', 'direct-site.co.tz')->where('status', 'approved')->where('client_id', $cA->id)->exists() && LinodeAuditLog::where('action', 'portal.domain_add')->exists(), 'recorded as approved + audited');
    // extra fields: ttl / soa_email / point_to_server
    fk([]);
    ok(call($uA, 'requestDomain', $sA->id, ['domain' => 'ttl-bad.com', 'ttl' => 12345])->getStatusCode() === 422, 'invalid TTL refused');
    ok(call($uA, 'requestDomain', $sA->id, ['domain' => 'mail-bad.com', 'soa_email' => 'not-an-email'])->getStatusCode() === 422, 'invalid SOA email refused');
    ok(call($uA, 'requestDomain', $sA->id, ['domain' => 'pt-bad.com', 'point_to_server' => 'maybe'])->getStatusCode() === 422, 'non-boolean point_to_server refused');
    ok(Http::recorded()->count() === 0, 'invalid extra fields make no Linode call');
    fk(['api.linode.com/v4/domains' => Http::response(['id' => 9210, 'domain' => 'zone-only.com', 'status' => 'active', 'soa_email' => 'me@example.test', 'ttl_sec' => 300], 200)]);
    $r = call($uA, 'requestDomain', $sA->id, ['domain' => 'zone-only.com', 'soa_email' => 'me@example.test', 'ttl' => 300, 'point_to_server' => false]);
    ok($r->getStatusCode() === 201 && j($r)['data']['pointed'] === false && j($r)['data']['nameservers'] === LinodeService::NAMESERVERS, 'point_to_server=false: created, nameservers returned');
    ok(Http::recorded(fn ($q) => str_contains($q->url(), '/records'))->count() === 0 && Http::recorded()->count() === 1, 'point_to_server=false: only the zone POST, no record POSTs');
    $zp = Http::recorded()->first()[0]->data();
    ok(($zp['soa_email'] ?? null) === 'me@example.test' && ($zp['ttl_sec'] ?? null) === 300, 'custom SOA email + TTL sent to Linode');
    LinodeDomainRequest::where('domain', 'zone-only.com')->delete();
    fk([]);
    foreach (['not a domain', 'x', 'bad_domain.com', 'a..com', ''] as $bad) {
        ok(call($uA, 'requestDomain', $sA->id, ['domain' => $bad])->getStatusCode() === 422, "invalid domain '$bad' rejected");
    }
    ok(call($uA, 'requestDomain', $sA->id, ['domain' => 'direct-site.co.tz'])->getStatusCode() === 422, 'domain already in Linode rejected');
    ok(call($uA, 'requestDomain', $sA->id, ['domain' => 'mine.co.tz'])->getStatusCode() === 422, 'another existing Linode domain rejected');
    ok(call($uA, 'requestDomain', $sB->id, ['domain' => 'sneaky.com'])->getStatusCode() === 404, "cannot add on another client's server");
    ok(Http::recorded()->count() === 0, 'refusals make no Linode call');
    fk($fakeAdd(9201, 'fail-site.com', '203.0.113.71'));
    fk(['api.linode.com/v4/domains' => Http::response(['errors' => [['reason' => 'Domain already exists']]], 400)]);
    $r = call($uA, 'requestDomain', $sA->id, ['domain' => 'fail-site.com']);
    ok($r->getStatusCode() === 422 && LinodeDomainRequest::where('domain', 'fail-site.com')->doesntExist() && !str_contains(json_encode(j($r)), 'Linode'), 'Linode failure -> generic 422, nothing recorded');
    // daily limit (10)
    for ($i = 0; $i < 9; $i++) LinodeDomainRequest::create(['tenant_id' => $tenantA->id, 'client_id' => $cA->id, 'linode_resource_id' => $sA->id, 'domain' => "filler$i.com", 'status' => 'approved', 'requested_by' => $uA->id]);
    fk([]);
    ok(call($uA, 'requestDomain', $sA->id, ['domain' => 'over-limit.com'])->getStatusCode() === 429, 'daily limit refused (429)');
    LinodeDomainRequest::where('domain', 'like', 'filler%')->delete();
    LinodeDomainRequest::where('domain', 'direct-site.co.tz')->delete();
    // legacy pending requests (created before direct add) can still be handled by staff
    foreach (['new-site.co.tz', 'site2.com', 'site3.com', 'site4.com', 'site5.com'] as $dm) LinodeDomainRequest::create(['tenant_id' => $tenantA->id, 'client_id' => $cA->id, 'linode_resource_id' => $sA->id, 'domain' => $dm, 'status' => 'pending', 'requested_by' => $uA->id]);
    LinodeDomainRequest::create(['tenant_id' => $tenantA->id, 'client_id' => $cB->id, 'linode_resource_id' => $sB->id, 'domain' => 'b-site.com', 'status' => 'pending', 'requested_by' => $uB->id]);

    // ---- staff: list, approve, reject
    $list = j(staffCall($staffA, 'index', null))['data'];
    ok(count($list) === 6 && collect($list)->every(fn ($x) => $x['status'] === 'pending') && collect($list)->firstWhere('domain', 'new-site.co.tz')['client_name'] === 'Portal A TEST', 'staff list shows pending requests with client + server');
    $req = LinodeDomainRequest::where('domain', 'new-site.co.tz')->first();
    fk([
        'api.linode.com/v4/domains' => Http::response(['id' => 9100, 'domain' => 'new-site.co.tz', 'status' => 'active', 'soa_email' => 'soa@example.test', 'ttl_sec' => 0], 200),
        'api.linode.com/v4/domains/9100/records*' => Http::sequence()
            ->push(['data' => [], 'page' => 1, 'pages' => 1, 'results' => 0])->push(['id' => 1, 'type' => 'A', 'name' => '', 'target' => '203.0.113.71', 'ttl_sec' => 0])
            ->push(['data' => [['id' => 1, 'type' => 'A', 'name' => '', 'target' => '203.0.113.71', 'ttl_sec' => 0]], 'page' => 1, 'pages' => 1, 'results' => 1])->push(['id' => 2, 'type' => 'A', 'name' => 'www', 'target' => '203.0.113.71', 'ttl_sec' => 0]),
    ]);
    $r = staffCall($staffA, 'approve', $req);
    $res = LinodeResource::where('type', 'domain')->where('label', 'new-site.co.tz')->first();
    ok($r->getStatusCode() === 200 && $req->fresh()->status === 'approved' && $req->fresh()->decided_by === $staffA->id && $req->fresh()->decided_at !== null, 'approve -> request approved with decider');
    ok($res && $res->client_id === $cA->id && ($res->meta['dns']['apex_ips'] ?? null) === ['203.0.113.71'], 'domain created in Linode (faked) and mapped to the client, DNS mapping recorded');
    ok(Http::recorded(fn ($q) => $q->method() === 'POST' && $q->url() === 'https://api.linode.com/v4/domains')->count() === 1
       && Http::recorded(fn ($q) => $q->method() === 'POST' && str_contains($q->url(), '/domains/9100/records'))->count() === 2
       && Http::recorded(fn ($q) => !in_array($q->method(), ['GET', 'POST']))->count() === 0, 'approve: 1 domain POST + 2 record POSTs, no other verbs (no DELETE)');
    ok(Notification::sent($cA, LinodeDomainRequestNotification::class)->where('event', 'approved')->count() === 1, 'client notified of approval');
    ok(LinodeAuditLog::where('action', 'domain_request.approve')->exists(), 'approve audited');
    // now visible in the client's domain list
    $d = j(call($uA, 'show', $sA->id))['data'];
    ok(collect($d['domains'])->pluck('name')->contains('new-site.co.tz') && collect($d['requests'])->firstWhere('domain', 'new-site.co.tz')['status'] === 'approved', 'client sees the approved domain + request status');
    // double decision
    fk([]);
    ok(staffCall($staffA, 'approve', $req)->getStatusCode() === 409 && staffCall($staffA, 'reject', $req)->getStatusCode() === 409 && Http::recorded()->count() === 0, 'already-decided request cannot be approved/rejected again, no HTTP');
    // approve when Linode says domain exists -> stays pending
    $req2 = LinodeDomainRequest::where('domain', 'site2.com')->first();
    fk(['api.linode.com/v4/domains' => Http::response(['errors' => [['reason' => 'Domain already exists']]], 400)]);
    $r = staffCall($staffA, 'approve', $req2);
    ok($r->getStatusCode() === 422 && $req2->fresh()->status === 'pending', 'Linode refusal -> 422, request stays pending');
    // reject
    fk([]);
    $req3 = LinodeDomainRequest::where('domain', 'site3.com')->first();
    $r = staffCall($staffA, 'reject', $req3, ['note' => 'Domain not owned by you']);
    ok($r->getStatusCode() === 200 && $req3->fresh()->status === 'rejected' && $req3->fresh()->note === 'Domain not owned by you' && Http::recorded()->count() === 0, 'reject -> rejected with note, no Linode call');
    ok(Notification::sent($cA, LinodeDomainRequestNotification::class)->where('event', 'rejected')->count() === 1, 'client notified of rejection');
    ok(LinodeResource::where('label', 'site3.com')->doesntExist(), 'rejected domain not created');
    $d = j(call($uA, 'show', $sA->id))['data'];
    ok(collect($d['requests'])->firstWhere('domain', 'site3.com')['note'] === 'Domain not owned by you', 'client sees rejection note');
    // server has no ipv4 -> approve refused
    $req4 = LinodeDomainRequest::where('domain', 'site4.com')->first();
    $sA->update(['ipv4' => []]);
    ok(staffCall($staffA, 'approve', $req4)->getStatusCode() === 422 && $req4->fresh()->status === 'pending', 'server without IPv4 -> approve refused');
    $sA->update(['ipv4' => ['203.0.113.71']]);

    // ---- support ticket
    fk([]);
    $tBefore = Ticket::withoutGlobalScopes()->where('client_id', $cA->id)->count();
    $r = call($uA, 'supportTicket', $sA->id, ['message' => 'Site is slow']);
    $t = Ticket::withoutGlobalScopes()->where('client_id', $cA->id)->latest('created_at')->first();
    $msg = $t?->replies()->first()?->message ?? '';
    ok($r->getStatusCode() === 201 && Ticket::withoutGlobalScopes()->where('client_id', $cA->id)->count() === $tBefore + 1, 'support ticket created via the portal ticket path');
    ok($t && $t->opened_by === $uA->id && $t->status === 'open' && str_starts_with($t->ticket_number, 'TKT-') && $t->tenant_id === $tenantA->id, 'ticket owned by client, opened_by portal user, numbered');
    ok(str_contains($msg, 'a-server') && str_contains($msg, '203.0.113.71') && str_contains($msg, 'eu-central') && str_contains($msg, 'Site is slow'), 'ticket body has server name/IP/region/status + message');
    ok(!str_contains($msg, '7001') && !str_contains($msg, TOKEN), 'ticket body has no remote id / token');
    ok(call($uA, 'supportTicket', $sB->id)->getStatusCode() === 404, "no ticket for another client's server");
    call($uA, 'supportTicket', $sA->id); call($uA, 'supportTicket', $sA->id);
    ok(call($uA, 'supportTicket', $sA->id)->getStatusCode() === 429, '4th server ticket in a day -> 429');

    // ---- tenant B isolation
    $otherStaff = User::withoutGlobalScopes()->where('tenant_id', '!=', $tenantA->id)->whereNotNull('tenant_id')->first();
    if ($otherStaff) {
        $tenantB = $otherStaff->tenant_id;
        $cX = Client::withoutGlobalScopes()->create(['tenant_id' => $tenantB, 'name' => 'Tenant B client TEST', 'phone' => '255700000299', 'email' => 'x@example.test', 'status' => 'active']);
        $uX = ClientUser::create(['client_id' => $cX->id, 'tenant_id' => $tenantB, 'name' => 'X', 'email' => 'x-portal@example.test', 'password' => 'x-Secret-123', 'role' => 'admin', 'is_active' => true]);
        fk([]);
        ok(call($uX, 'reboot', $sA->id, ['confirm_label' => 'a-server'])->getStatusCode() === 404 && call($uX, 'show', $sA->id)->getStatusCode() === 404, 'tenant B portal user cannot touch tenant A server');
        auth()->setUser($otherStaff);
        ok(LinodeDomainRequest::find($req4->id) === null, 'tenant B staff cannot resolve tenant A request (scoped -> 404)');
        ok(collect(j(staffCall($otherStaff, 'index', null))['data'])->where('domain', 'site4.com')->isEmpty(), 'tenant B staff list does not include tenant A requests');
    } else echo "SKIP no second tenant user\n";

    // ---- staff permission plumbing
    ok(DB::table('permissions')->where('name', 'linode.manage')->exists(), 'approve/reject use existing linode.manage permission (no new permission needed)');
    $routes = collect(app('router')->getRoutes()->getRoutes())->filter(fn ($r) => str_contains($r->uri(), 'domain-requests') && str_starts_with($r->uri(), 'api/linode'));
    ok($routes->count() === 3 && $routes->every(fn ($r) => in_array('permission:linode.manage', $r->gatherMiddleware(), true)), 'staff routes are behind permission:linode.manage');
    $pr = collect(app('router')->getRoutes()->getRoutes())->filter(fn ($r) => str_starts_with($r->uri(), 'api/portal/linode'));
    ok($pr->count() === 9 && $pr->every(fn ($r) => in_array('client_portal', $r->gatherMiddleware(), true)) && $pr->every(fn ($r) => !in_array('DELETE', $r->methods(), true)), 'portal routes behind client_portal auth group, no DELETE');
} catch (\Throwable $e) {
    $fail++; echo 'FAIL exception ' . $e->getMessage() . ' @' . $e->getFile() . ':' . $e->getLine() . "\n";
}
DB::rollBack();
echo $fail ? "$fail FAILED\n" : "ALL PASSED\n";
exit($fail ? 1 : 0);

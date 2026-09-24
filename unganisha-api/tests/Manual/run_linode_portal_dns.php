<?php
// php tests/Manual/run_linode_portal_dns.php  (live DB rolled back; Linode fully faked - NO real calls)
require __DIR__ . '/../../vendor/autoload.php';
$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Http\Controllers\Portal\PortalLinodeController;
use App\Models\{Client, ClientSubscription, ClientUser, LinodeAccount, LinodeAuditLog, LinodeResource, ProductService, Tenant, User};
use App\Services\Linode\LinodeService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\{DB, Http};

const TOKEN = 'lin_SECRET_TOKEN_abcdefghijklmnopqrstuvwxyz1234';
LinodeService::$sleepOnRateLimit = false;
LinodeService::$paginatedGapMs = 0;
$fail = 0;
function ok($c, $m) { global $fail; if (!$c) { $fail++; echo "FAIL $m\n"; } else echo "PASS $m\n"; }
function j($r) { return $r->getData(true); }
function verbs() { return Http::recorded()->map(fn ($p) => $p[0]->method())->countBy()->all(); }
/** Fake Linode DNS for domain $did with a mutable record list. */
function fakeDns(int $did, array &$records) {
    Http::swap(new \Illuminate\Http\Client\Factory()); Http::preventStrayRequests();
    Http::fake(function ($req) use ($did, &$records) {
        $u = parse_url($req->url())['path'];
        if ($req->method() === 'GET' && $u === "/v4/domains/$did/records") return Http::response(['data' => $records, 'page' => 1, 'pages' => 1, 'results' => count($records)]);
        if ($req->method() === 'POST' && $u === "/v4/domains/$did/records") { $b = $req->data(); $b['id'] = 900 + count($records); $records[] = $b; return Http::response($b); }
        if ($req->method() === 'PUT' && preg_match("#^/v4/domains/$did/records/(\d+)$#", $u, $m)) { $b = $req->data(); $b['id'] = (int) $m[1]; return Http::response($b); }
        return Http::response(['errors' => [['reason' => 'LINODE INTERNAL scope domains:read_write ' . TOKEN]]], 500);
    });
}
function call(ClientUser $u, string $m, array $args, array $d = [], string $http = 'POST') {
    auth()->setUser($u);
    $rq = Request::create('/x', $http, $d); $rq->setUserResolver(fn () => $u); app()->instance('request', $rq);
    try { return app(PortalLinodeController::class)->$m($rq, ...$args); }
    catch (\Symfony\Component\HttpKernel\Exception\HttpException $e) { return response()->json(['message' => $e->getMessage()], $e->getStatusCode()); }
    catch (\Illuminate\Validation\ValidationException $e) { return response()->json(['message' => $e->getMessage()], 422); }
}

DB::beginTransaction();
try {
    $tenantA = Tenant::withoutGlobalScopes()->where('name', 'MoBilling Test Co')->firstOrFail();
    $staffA = User::withoutGlobalScopes()->where('tenant_id', $tenantA->id)->firstOrFail();
    auth()->setUser($staffA);
    $acct = new LinodeAccount(['label' => 'T', 'token' => TOKEN, 'token_hint' => '1234', 'status' => 'active', 'soa_email' => 'soa@example.test']);
    $acct->tenant_id = $tenantA->id; $acct->save();
    $cA = Client::create(['name' => 'DNS A TEST', 'phone' => '255700000301', 'email' => 'a@example.test', 'status' => 'active']);
    $cB = Client::create(['name' => 'DNS B TEST', 'phone' => '255700000302', 'email' => 'b@example.test', 'status' => 'active']);
    $prod = ProductService::create(['type' => 'service', 'name' => 'Linode Server TEST', 'price' => 1000, 'tax_percent' => 0, 'unit' => 'pcs', 'category' => 'Linode Servers', 'billing_cycle' => 'yearly', 'provisioning_type' => 'linode', 'portal_visible' => false, 'is_active' => true]);
    $mkSub = fn ($c) => ClientSubscription::create(['client_id' => $c->id, 'product_service_id' => $prod->id, 'label' => 'srv', 'quantity' => 1, 'start_date' => '2026-01-01', 'expire_date' => '2027-01-01', 'status' => 'active']);
    $mkSrv = fn ($id, $label, $ip, $c, $sub) => LinodeResource::create(['tenant_id' => $tenantA->id, 'linode_account_id' => $acct->id, 'type' => 'instance', 'remote_id' => $id, 'label' => $label, 'status' => 'running', 'region' => 'eu-central', 'ipv4' => [$ip], 'client_id' => $c->id, 'client_subscription_id' => $sub->id]);
    $sA = $mkSrv('8001', 'a-server', '203.0.113.81', $cA, $mkSub($cA));
    $sA2 = $mkSrv('8003', 'a-server2', '203.0.113.83', $cA, $mkSub($cA));
    $sB = $mkSrv('8002', 'b-server', '203.0.113.82', $cB, $mkSub($cB));
    $mkUser = fn ($c, $role, $email) => ClientUser::create(['client_id' => $c->id, 'tenant_id' => $tenantA->id, 'name' => 'U', 'email' => $email, 'password' => 'x-Secret-123', 'role' => $role, 'is_active' => true]);
    $uA = $mkUser($cA, 'admin', 'da@example.test'); $uAv = $mkUser($cA, 'viewer', 'dav@example.test'); $uB = $mkUser($cB, 'admin', 'db@example.test');
    $dom = fn ($label, $client, $ips, $rid, $extra = []) => LinodeResource::create(['tenant_id' => $tenantA->id, 'linode_account_id' => $acct->id, 'type' => 'domain', 'remote_id' => $rid, 'label' => $label, 'status' => 'active', 'client_id' => $client?->id,
        'meta' => ['dns' => ['apex_ips' => $ips, 'www_ips' => $ips, 'fetched_at' => now()->toIso8601String()]]] + $extra);
    $dMine = $dom('mine.co.tz', $cA, ['203.0.113.81'], '9300');
    $dOther = $dom('otherclient.co.tz', $cB, ['203.0.113.81'], '9301');
    $dElse = $dom('elsewhere.co.tz', $cA, ['203.0.113.83'], '9302');      // A's, but mapped to A's OTHER server
    $dBsrv = $dom('bside.co.tz', $cB, ['203.0.113.82'], '9303');
    $recs = [
        ['id' => 1, 'type' => 'NS', 'name' => '', 'target' => 'ns1.linode.com', 'ttl_sec' => 0],
        ['id' => 2, 'type' => 'SOA', 'name' => '', 'target' => 'ns1.linode.com', 'ttl_sec' => 0],
        ['id' => 3, 'type' => 'A', 'name' => '', 'target' => '203.0.113.81', 'ttl_sec' => 0],
        ['id' => 4, 'type' => 'TXT', 'name' => '', 'target' => 'v=spf1 -all', 'ttl_sec' => 0],
    ];
    $args = fn ($s, $d, ...$more) => [$s->id, $d->id, ...$more];

    // ---- list
    fakeDns(9300, $recs);
    $r = call($uA, 'dnsRecords', $args($sA, $dMine), [], 'GET');
    $body = json_encode(j($r));
    ok($r->getStatusCode() === 200 && count(j($r)['data']) === 4, 'own domain: records listed live');
    ok(collect(j($r)['data'])->where('locked', true)->pluck('type')->sort()->values()->all() === ['NS', 'SOA'], 'NS/SOA flagged locked');
    ok(j($r)['meta']['nameservers'] === LinodeService::NAMESERVERS, 'nameserver guidance returned');
    ok(verbs() === ['GET' => 1], 'exactly one GET, nothing else');
    ok(!str_contains($body, TOKEN) && !str_contains($body, 'remote_id') && !str_contains($body, '9300'), 'no secrets / remote ids in list');
    fakeDns(9300, $recs);
    ok(call($uAv, 'dnsRecords', $args($sA, $dMine), [], 'GET')->getStatusCode() === 200, 'viewer may read');

    // ---- 404s (no HTTP at all)
    fakeDns(9300, $recs);
    ok(call($uA, 'dnsRecords', $args($sA, $dOther), [], 'GET')->getStatusCode() === 404, "other client's domain -> 404 (list)");
    ok(call($uA, 'dnsRecordStore', $args($sA, $dOther), ['type' => 'A', 'name' => 'x', 'target' => '1.2.3.4'])->getStatusCode() === 404, "other client's domain -> 404 (add)");
    ok(call($uA, 'dnsRecords', $args($sA, $dElse), [], 'GET')->getStatusCode() === 404, 'domain not mapped to this server -> 404');
    ok(call($uA, 'dnsRecordUpdate', $args($sA, $dElse, '3'), ['type' => 'A', 'name' => '', 'target' => '1.2.3.4'], 'PUT')->getStatusCode() === 404, 'unmapped domain -> 404 (edit)');
    ok(call($uA, 'dnsRecords', $args($sB, $dBsrv), [], 'GET')->getStatusCode() === 404, "other client's server -> 404");
    ok(call($uB, 'dnsRecords', $args($sA, $dMine), [], 'GET')->getStatusCode() === 404, 'reverse direction -> 404');
    ok(call($uA, 'dnsRecords', $args($sA, $sA), [], 'GET')->getStatusCode() === 404, 'instance id as domain -> 404');
    ok(call($uA, 'dnsRecords', [$sA->id, 'nope'], [], 'GET')->getStatusCode() === 404, 'unknown domain -> 404');
    ok(call($uA, 'dnsPointToServer', $args($sA, $dOther))->getStatusCode() === 404, 'point-to-server on other domain -> 404');
    ok(Http::recorded()->count() === 0, 'no Linode call for any 404');

    // ---- add
    fakeDns(9300, $recs);
    $r = call($uA, 'dnsRecordStore', $args($sA, $dMine), ['type' => 'A', 'name' => 'blog', 'target' => '198.51.100.9', 'ttl_sec' => 0]);
    ok($r->getStatusCode() === 201 && j($r)['data']['name'] === 'blog', 'add A record ok');
    ok(verbs() === ['GET' => 2, 'POST' => 1] && Http::recorded(fn ($q) => $q->method() === 'POST' && str_ends_with($q->url(), '/domains/9300/records'))->count() === 1, 'faked calls: list (cap+validate) then exactly one POST');
    $a = LinodeAuditLog::where('action', 'portal.dns_record_add')->latest('created_at')->first();
    ok($a && $a->request['client_id'] === $cA->id && $a->request['domain'] === 'mine.co.tz' && $a->request['record_type'] === 'A' && $a->request['record_name'] === 'blog' && !str_contains(json_encode($a->toArray()), TOKEN), 'add audited (client, domain, type, name; no secrets)');
    foreach ([['type' => 'MX', 'name' => '', 'target' => 'mail.example.com', 'priority' => 10],
              ['type' => 'AAAA', 'name' => 'v6', 'target' => '2001:db8::1'], ['type' => 'CNAME', 'name' => 'shop', 'target' => 'shops.example.com'],
              ['type' => 'TXT', 'name' => '_dmarc', 'target' => 'v=DMARC1; p=none'], ['type' => 'SRV', 'name' => '_sip._tcp', 'target' => 'sip.example.com', 'priority' => 5, 'weight' => 1, 'port' => 5060],
              ['type' => 'CAA', 'name' => '', 'target' => 'letsencrypt.org', 'tag' => 'issue']] as $in) {
        fakeDns(9300, $recs);
        $r = call($uA, 'dnsRecordStore', $args($sA, $dMine), $in);
        ok($r->getStatusCode() === 201, "add {$in['type']} ok" . ($r->getStatusCode() === 201 ? '' : ' ' . json_encode(j($r))));
    }
    // ---- refusals with no write
    fakeDns(9300, $recs);
    ok(call($uAv, 'dnsRecordStore', $args($sA, $dMine), ['type' => 'A', 'name' => 'v', 'target' => '1.2.3.4'])->getStatusCode() === 403, 'viewer add -> 403');
    ok(call($uAv, 'dnsRecordUpdate', $args($sA, $dMine, '3'), ['type' => 'A', 'name' => '', 'target' => '1.2.3.4'], 'PUT')->getStatusCode() === 403, 'viewer edit -> 403');
    ok(call($uAv, 'dnsPointToServer', $args($sA, $dMine))->getStatusCode() === 403, 'viewer point-to-server -> 403');
    ok(Http::recorded()->count() === 0, 'viewer refusals make no Linode call');
    foreach ([['type' => 'NS', 'name' => '', 'target' => 'ns9.evil.com'], ['type' => 'SOA', 'name' => '', 'target' => 'x.com'], ['type' => 'A', 'name' => '', 'target' => 'not-an-ip'],
              ['type' => 'A', 'name' => 'bad name!', 'target' => '1.2.3.4'], ['type' => 'CNAME', 'name' => '', 'target' => 'x.example.com'], ['type' => 'ZZZ', 'name' => 'a', 'target' => 'b'],
              ['type' => 'A', 'name' => 'blog', 'target' => '198.51.100.9', 'ttl_sec' => 0]] as $in) {
        fakeDns(9300, $recs);
        $r = call($uA, 'dnsRecordStore', $args($sA, $dMine), $in);
        ok($r->getStatusCode() === 422 && !Http::recorded(fn ($q) => $q->method() !== 'GET')->count(), "invalid/duplicate/locked add refused ({$in['type']} '{$in['name']}'), no write");
    }
    ok(call($uA, 'dnsRecordStore', $args($sA, $dMine), ['name' => 'x'])->getStatusCode() === 422, 'missing type/target -> 422');

    // ---- edit
    fakeDns(9300, $recs);
    $r = call($uA, 'dnsRecordUpdate', $args($sA, $dMine, '4'), ['type' => 'TXT', 'name' => '', 'target' => 'v=spf1 include:example.com -all', 'ttl_sec' => 0], 'PUT');
    ok($r->getStatusCode() === 200 && verbs() === ['GET' => 1, 'PUT' => 1], 'edit TXT: one GET + exactly one PUT');
    ok(Http::recorded(fn ($q) => $q->method() === 'PUT' && str_ends_with($q->url(), '/domains/9300/records/4'))->count() === 1, 'PUT hit the right record');
    $a = LinodeAuditLog::where('action', 'portal.dns_record_edit')->latest('created_at')->first();
    ok($a && $a->request['client_id'] === $cA->id && $a->request['domain'] === 'mine.co.tz' && $a->request['record_type'] === 'TXT', 'edit audited');
    foreach (['1' => 'NS', '2' => 'SOA'] as $id => $t) {
        fakeDns(9300, $recs);
        $r = call($uA, 'dnsRecordUpdate', $args($sA, $dMine, (string) $id), ['type' => $t, 'name' => '', 'target' => 'ns9.evil.com'], 'PUT');
        ok($r->getStatusCode() === 422 && verbs() === ['GET' => 1], "$t edit refused, no PUT");
    }
    fakeDns(9300, $recs);
    ok(call($uA, 'dnsRecordUpdate', $args($sA, $dMine, '99999'), ['type' => 'A', 'name' => '', 'target' => '1.2.3.4'], 'PUT')->getStatusCode() === 422 && !Http::recorded(fn ($q) => $q->method() === 'PUT')->count(), 'unknown record id refused');
    ok(call($uA, 'dnsRecordUpdate', $args($sA, $dMine, 'abc'), ['type' => 'A', 'name' => '', 'target' => '1.2.3.4'], 'PUT')->getStatusCode() === 404, 'non-numeric record id -> 404');

    // ---- point to server (idempotent)
    $recs2 = [['id' => 1, 'type' => 'NS', 'name' => '', 'target' => 'ns1.linode.com', 'ttl_sec' => 0]];
    fakeDns(9300, $recs2);
    $r = call($uA, 'dnsPointToServer', $args($sA, $dMine));
    ok($r->getStatusCode() === 200 && j($r)['data']['created'] === 2 && Http::recorded(fn ($q) => $q->method() === 'POST' && $q->data()['target'] === '203.0.113.81')->count() === 2, 'point-to-server creates A + www to the server IPv4');
    fakeDns(9300, $recs2);
    $r = call($uA, 'dnsPointToServer', $args($sA, $dMine));
    ok($r->getStatusCode() === 200 && j($r)['data']['created'] === 0 && !Http::recorded(fn ($q) => $q->method() !== 'GET')->count(), 'second run: identical records ignored, no writes');
    ok(LinodeAuditLog::where('action', 'portal.dns_point_to_server')->where('request->client_id', $cA->id)->count() === 2, 'point-to-server audited');

    // ---- Linode failure -> generic
    Http::swap(new \Illuminate\Http\Client\Factory()); Http::preventStrayRequests();
    Http::fake(['api.linode.com/*' => Http::response(['errors' => [['reason' => 'OAuth token missing scope domains:read_write']]], 403)]);
    $r = call($uA, 'dnsRecordStore', $args($sA, $dMine), ['type' => 'A', 'name' => 'zz', 'target' => '1.2.3.4']);
    $m = json_encode(j($r));
    ok($r->getStatusCode() === 422 && !str_contains(strtolower($m), 'scope') && !str_contains(strtolower($m), 'oauth') && !str_contains($m, TOKEN), 'Linode error -> generic client-safe message');
    $r = call($uA, 'dnsRecords', $args($sA, $dMine), [], 'GET');
    ok($r->getStatusCode() === 422 && !str_contains(strtolower(json_encode(j($r))), 'scope'), 'list failure -> generic');

    // ---- record cap
    $many = []; for ($i = 1; $i <= 50; $i++) $many[] = ['id' => $i, 'type' => 'TXT', 'name' => "t$i", 'target' => "v$i", 'ttl_sec' => 0];
    fakeDns(9300, $many);
    $r = call($uA, 'dnsRecordStore', $args($sA, $dMine), ['type' => 'A', 'name' => 'cap', 'target' => '1.2.3.4']);
    ok($r->getStatusCode() === 422 && !Http::recorded(fn ($q) => $q->method() !== 'GET')->count(), 'record cap (50) refuses add, no POST');
    fakeDns(9300, $many);
    ok(call($uA, 'dnsPointToServer', $args($sA, $dMine))->getStatusCode() === 422 && !Http::recorded(fn ($q) => $q->method() !== 'GET')->count(), 'record cap also blocks point-to-server');

    // ---- rate limit (20 writes / client / hour)
    LinodeAuditLog::whereIn('action', ['portal.dns_record_add', 'portal.dns_record_edit', 'portal.dns_point_to_server'])->delete();
    for ($i = 0; $i < 20; $i++) LinodeAuditLog::create(['tenant_id' => $tenantA->id, 'user_id' => $uA->id, 'linode_account_id' => $acct->id, 'action' => $i % 2 ? 'portal.dns_record_add' : 'portal.dns_record_edit', 'target' => 'x', 'request' => ['client_id' => $cA->id], 'response_status' => 200]);
    $recs3 = $recs; fakeDns(9300, $recs3);
    ok(call($uA, 'dnsRecordStore', $args($sA, $dMine), ['type' => 'A', 'name' => 'lim', 'target' => '1.2.3.4'])->getStatusCode() === 429, '21st write in an hour -> 429 (add)');
    ok(call($uA, 'dnsRecordUpdate', $args($sA, $dMine, '4'), ['type' => 'TXT', 'name' => '', 'target' => 'x'], 'PUT')->getStatusCode() === 429, '429 also on edit');
    ok(call($uA, 'dnsPointToServer', $args($sA, $dMine))->getStatusCode() === 429 && Http::recorded()->count() === 0, '429 also on point-to-server, no Linode call');
    fakeDns(9301, $recs3);
    ok(call($uB, 'dnsRecordStore', $args($sB, $dBsrv), ['type' => 'A', 'name' => 'ok', 'target' => '1.2.3.4'])->getStatusCode() !== 429, "client A's limit does not block client B");
    LinodeAuditLog::whereIn('action', ['portal.dns_record_add', 'portal.dns_record_edit'])->update(['created_at' => now()->subHours(2)]);
    fakeDns(9300, $recs3);
    ok(call($uA, 'dnsRecordStore', $args($sA, $dMine), ['type' => 'A', 'name' => 'later', 'target' => '1.2.3.4'])->getStatusCode() === 201, 'writes older than an hour do not count');

    // ---- tenant isolation
    $otherStaff = User::withoutGlobalScopes()->where('tenant_id', '!=', $tenantA->id)->whereNotNull('tenant_id')->first();
    if ($otherStaff) {
        $cX = Client::withoutGlobalScopes()->create(['tenant_id' => $otherStaff->tenant_id, 'name' => 'Tenant B client TEST', 'phone' => '255700000399', 'email' => 'x@example.test', 'status' => 'active']);
        $uX = ClientUser::create(['client_id' => $cX->id, 'tenant_id' => $otherStaff->tenant_id, 'name' => 'X', 'email' => 'x-dns@example.test', 'password' => 'x-Secret-123', 'role' => 'admin', 'is_active' => true]);
        fakeDns(9300, $recs);
        ok(call($uX, 'dnsRecords', $args($sA, $dMine), [], 'GET')->getStatusCode() === 404 && call($uX, 'dnsRecordStore', $args($sA, $dMine), ['type' => 'A', 'name' => 'x', 'target' => '1.2.3.4'])->getStatusCode() === 404 && Http::recorded()->count() === 0, 'other-tenant portal user -> 404, no call');
    } else echo "SKIP no second tenant user\n";

    // ---- routes
    $pr = collect(app('router')->getRoutes()->getRoutes())->filter(fn ($r) => str_starts_with($r->uri(), 'api/portal/linode') && str_contains($r->uri(), 'domains/'));
    ok($pr->count() === 4 && $pr->every(fn ($r) => in_array('client_portal', $r->gatherMiddleware(), true) && !in_array('DELETE', $r->methods(), true)), 'DNS routes behind client_portal, no DELETE');
    // ---- overview exposes domain id for the UI
    fakeDns(9300, $recs);
    $ov = call($uA, 'show', [$sA->id][0] ? [$sA->id] : [], [], 'GET');
    ok(collect(j($ov)['data']['domains'])->pluck('name')->all() === ['mine.co.tz'] && !empty(j($ov)['data']['domains'][0]['id']) && !str_contains(json_encode(j($ov)), TOKEN), 'overview lists only own mapped domain with its id');
} catch (\Throwable $e) {
    $fail++; echo 'FAIL exception ' . $e->getMessage() . ' @' . $e->getFile() . ':' . $e->getLine() . "\n";
}
DB::rollBack();
echo $fail ? "$fail FAILED\n" : "ALL PASSED\n";
exit($fail ? 1 : 0);

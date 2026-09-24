<?php
// php tests/Manual/run_linode.php  (live DB, everything rolled back, Linode fully faked - NO real API calls)
require __DIR__ . '/../../vendor/autoload.php';
$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Http\Controllers\LinodeController;
use App\Http\Middleware\CheckPermission;
use App\Models\{Client, LinodeAccount, LinodeAuditLog, LinodeResource, Tenant, User};
use App\Services\Linode\LinodeService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\{DB, Http, Log};

const TOKEN = 'lin_SECRET_TOKEN_abcdefghijklmnopqrstuvwxyz1234';
LinodeService::$sleepOnRateLimit = false;
$fail = 0;
function ok($c, $m) { global $fail; if (!$c) { $fail++; echo "FAIL $m\n"; } else echo "PASS $m\n"; }
function fk($x) { Http::swap(new \Illuminate\Http\Client\Factory()); Http::fake($x); }
function j($r) { return $r->getData(true); }
function call($method, $params = [], ...$args) { return app(LinodeController::class)->$method(...$args); }
function req(array $d = []) { return Request::create('/x', 'POST', $d); }
function bind(array $d) { app()->instance('request', req($d)); return app('request'); }

$inst = fn ($id, $label, $ip) => ['id' => $id, 'label' => $label, 'status' => 'running', 'region' => 'eu-central', 'type' => 'g6-nanode-1', 'ipv4' => [$ip], 'ipv6' => '2600:3c00::1/128', 'tags' => [], 'image' => 'linode/ubuntu22.04', 'specs' => ['disk' => 25600], 'created' => '2026-01-01T00:00:00'];
$page = fn ($data) => ['data' => $data, 'page' => 1, 'pages' => 1, 'results' => count($data)];

DB::beginTransaction();
try {
    $tenantA = Tenant::withoutGlobalScopes()->where('name', 'MoBilling Test Co')->firstOrFail();
    $userA = User::withoutGlobalScopes()->where('tenant_id', $tenantA->id)->firstOrFail();
    auth()->login($userA);

    // capture logs
    $logged = [];
    Log::listen(function ($e) use (&$logged) { $logged[] = $e->message . json_encode($e->context); });

    // ---- verify: 401 / 403 / success
    fk(['api.linode.com/v4/domains*' => Http::response(['errors' => [['reason' => 'Invalid OAuth Token']]], 401)]);
    $r = app(LinodeController::class)->storeAccount(bind(['label' => 'L', 'token' => TOKEN]));
    ok($r->getStatusCode() === 422 && str_contains(j($r)['message'], 'rejected the token'), 'verify 401 refused with readable message');
    ok(LinodeAccount::count() === 0, '401 does not save account');

    fk([
        'api.linode.com/v4/domains*' => Http::response(['errors' => [['reason' => 'Your OAuth token is not authorized to use this endpoint.']]], 403),
        'api.linode.com/v4/linode/instances*' => Http::response($page([])),
    ]);
    $r = app(LinodeController::class)->storeAccount(bind(['label' => 'Scope', 'token' => TOKEN]));
    ok($r->getStatusCode() === 201 && str_contains(j($r)['message'], 'domains:read_only'), 'verify 403 names missing scope domains:read_only');

    fk(['api.linode.com/v4/domains*' => Http::response($page([])), 'api.linode.com/v4/linode/instances*' => Http::response($page([]))]);
    $r = app(LinodeController::class)->storeAccount(bind(['label' => 'Main', 'token' => TOKEN, 'soa_email' => 'dns@biz.co.tz']));
    $acct = LinodeAccount::where('label', 'Main')->firstOrFail();
    ok($r->getStatusCode() === 201 && $acct->status === 'active' && $acct->last_verified_at, 'verify success saves active account');
    $body = json_encode(j($r), JSON_UNESCAPED_UNICODE);
    ok(!str_contains($body, TOKEN) && !str_contains($body, 'SECRET'), 'token absent from create response');
    ok(str_contains($body, '••••1234'), 'masked hint returned');
    ok(!str_contains(json_encode($acct->toArray()), TOKEN) && !array_key_exists('token', $acct->toArray()), 'token hidden from model array');
    ok(DB::table('linode_accounts')->where('id', $acct->id)->value('token') !== TOKEN, 'token stored encrypted');

    // ---- sync
    fk([
        'api.linode.com/v4/linode/instances*' => Http::response($page([$inst(101, 'web-1', '172.105.1.10'), $inst(102, 'web-2', '172.105.1.11')])),
        'api.linode.com/v4/domains*' => Http::response($page([['id' => 7, 'domain' => 'old.example.com', 'status' => 'active', 'type' => 'master', 'soa_email' => 'a@b.co', 'ttl_sec' => 0]])),
    ]);
    $r = app(LinodeController::class)->sync($acct);
    ok(LinodeResource::where('type', 'instance')->count() === 2 && LinodeResource::where('type', 'domain')->count() === 1, 'sync upserts instances + domains');
    ok(LinodeResource::where('remote_id', '101')->value('plan') === 'g6-nanode-1', 'sync stores plan');
    fk([
        'api.linode.com/v4/linode/instances*' => Http::response($page([$inst(101, 'web-1', '172.105.1.10')])),
        'api.linode.com/v4/domains*' => Http::response($page([['id' => 7, 'domain' => 'old.example.com', 'status' => 'active', 'type' => 'master']])),
    ]);
    app(LinodeController::class)->sync($acct);
    ok(LinodeResource::where('remote_id', '102')->value('status') === 'gone', 'sync marks removed as gone');
    ok(LinodeResource::where('type', 'instance')->count() === 2, 'sync is idempotent (no duplicates)');

    // 429 retry
    fk(['api.linode.com/v4/linode/instances*' => Http::sequence()->push([], 429, ['Retry-After' => '1'])->push($page([$inst(101, 'web-1', '172.105.1.10')])),
                'api.linode.com/v4/domains*' => Http::response($page([['id' => 7, 'domain' => 'old.example.com', 'status' => 'active', 'type' => 'master']]))]);
    $r = app(LinodeController::class)->sync($acct);
    ok($r->getStatusCode() === 200, '429 retried then succeeds');

    // ---- add domain happy path
    $web1 = LinodeResource::where('remote_id', '101')->firstOrFail();
    $posted = [];
    fk(function ($request) use (&$posted, $page) {
        $u = $request->url(); $m = $request->method();
        if ($m === 'POST' && str_ends_with($u, '/domains')) { $posted[] = $request->data(); return Http::response(['id' => 55, 'domain' => $request['domain'], 'type' => 'master', 'status' => 'active', 'soa_email' => $request['soa_email'], 'ttl_sec' => 300]); }
        if ($m === 'POST' && str_contains($u, '/domains/55/records')) { $posted[] = $request->data(); return Http::response(['id' => rand(1, 999)] + $request->data()); }
        if ($m === 'GET' && str_contains($u, '/domains/55/records')) return Http::response($page([['id' => 1, 'type' => 'NS', 'name' => '', 'target' => 'ns1.linode.com'], ['id' => 2, 'type' => 'SOA', 'name' => '', 'target' => 'x']]));
        return Http::response(['errors' => [['reason' => 'unexpected']]], 500);
    });
    $r = app(LinodeController::class)->storeDomain(bind(['account_id' => $acct->id, 'domain' => 'Newsite.co.tz', 'ttl' => 300, 'server_id' => $web1->id]));
    $d = j($r);
    ok($r->getStatusCode() === 201 && $d['data']['label'] === 'newsite.co.tz', 'add domain 201, name lowercased');
    ok($posted[0]['type'] === 'master' && $posted[0]['soa_email'] === 'dns@biz.co.tz' && $posted[0]['ttl_sec'] === 300, 'domain created master with default soa email');
    $recs = array_slice($posted, 1);
    ok(count($recs) === 2 && $recs[0]['type'] === 'A' && $recs[0]['name'] === '' && $recs[0]['target'] === '172.105.1.10' && $recs[1]['name'] === 'www', 'A (root) + A www point to instance ipv4');
    ok($d['data']['nameservers'] === LinodeService::NAMESERVERS, 'nameservers returned');
    ok(LinodeResource::where('type', 'domain')->where('label', 'newsite.co.tz')->exists(), 'resource upserted');

    // ---- duplicates
    $r = app(LinodeController::class)->storeDomain(bind(['account_id' => $acct->id, 'domain' => 'newsite.co.tz']));
    ok($r->getStatusCode() === 422 && str_contains(j($r)['message'], 'already'), 'duplicate refused from cache');
    fk(['api.linode.com/v4/domains' => Http::response(['errors' => [['field' => 'domain', 'reason' => 'That domain already exists']]], 400)]);
    $r = app(LinodeController::class)->storeDomain(bind(['account_id' => $acct->id, 'domain' => 'taken.com']));
    ok($r->getStatusCode() === 422 && str_contains(j($r)['message'], 'already exists'), 'duplicate refused from API 400');

    // ---- validation
    foreach (['http://x.com', 'nodot', 'a b.com', 'x.com.'] as $bad) {
        $r = app(LinodeController::class)->storeDomain(bind(['account_id' => $acct->id, 'domain' => $bad]));
        ok($r->getStatusCode() === 422, "bad domain '$bad' refused");
    }
    $r = app(LinodeController::class)->storeDomain(bind(['account_id' => $acct->id, 'domain' => 'good.com', 'ttl' => 301]));
    ok($r->getStatusCode() === 422 && str_contains(j($r)['message'], 'TTL'), 'invalid TTL refused');

    $existing = [['id' => 9, 'type' => 'A', 'name' => 'www', 'target' => '1.2.3.4'], ['id' => 10, 'type' => 'CNAME', 'name' => 'blog', 'target' => 'x.com']];
    $throws = function (array $rec, ?string $needle = null, ?string $ign = null) use ($existing) {
        try { LinodeService::validateRecord($rec, $existing, $ign); return false; } catch (\InvalidArgumentException $e) { return $needle ? str_contains($e->getMessage(), $needle) : true; }
    };
    ok($throws(['type' => 'NS', 'name' => '', 'target' => 'ns9.evil.com'], 'managed by Linode'), 'NS create refused');
    ok($throws(['type' => 'SOA', 'name' => '', 'target' => 'x'], 'managed by Linode'), 'SOA refused');
    ok($throws(['type' => 'CNAME', 'name' => '', 'target' => 'x.com'], 'apex'), 'apex CNAME refused');
    ok($throws(['type' => 'A', 'name' => 'www', 'target' => '1.2.3.4'], 'identical'), 'identical record refused');
    ok($throws(['type' => 'A', 'name' => 'www', 'target' => 'nope'], 'IPv4'), 'bad A target refused');
    ok($throws(['type' => 'A', 'name' => 'a', 'target' => '1.1.1.1', 'ttl_sec' => 5], 'TTL'), 'bad record TTL refused');
    ok($throws(['type' => 'MX', 'name' => '', 'target' => 'mail.x.com'], 'Priority'), 'MX needs priority');
    ok($throws(['type' => 'A', 'name' => 'blog', 'target' => '1.1.1.1'], 'CNAME'), 'A next to CNAME refused');
    ok($throws(['type' => 'CNAME', 'name' => 'www', 'target' => 'x.com'], 'CNAME cannot share'), 'CNAME next to A refused');
    ok(!$throws(['type' => 'A', 'name' => 'www', 'target' => '1.2.3.4'], null, '9'), 'editing self is not a duplicate');
    ok(!$throws(['type' => 'TXT', 'name' => '_dmarc', 'target' => 'v=DMARC1; p=none']), 'valid TXT accepted');

    // NS/SOA edit/delete via service (locked, from listing)
    $dom = LinodeResource::where('label', 'newsite.co.tz')->firstOrFail();
    fk(['api.linode.com/v4/domains/55/records*' => Http::response($page([['id' => 1, 'type' => 'NS', 'name' => '', 'target' => 'ns1.linode.com']]))]);
    $r = app(LinodeController::class)->updateRecord(bind(['type' => 'A', 'name' => '', 'target' => '1.1.1.1']), $dom, '1');
    ok($r->getStatusCode() === 422 && str_contains(j($r)['message'], 'managed by Linode'), 'NS record edit refused');
    ok(!method_exists(LinodeController::class, 'destroyRecord') && !method_exists(\App\Services\Linode\LinodeService::class, 'deleteRecord'), 'no record-delete code path exists');
    $req = new ReflectionMethod(\App\Services\Linode\LinodeService::class, 'request'); $req->setAccessible(true);
    $threw = false; try { $req->invoke(new \App\Services\Linode\LinodeService($dom->account ?? LinodeAccount::firstOrFail()), 'DELETE', '/domains/55'); } catch (\Throwable $e) { $threw = str_contains($e->getMessage(), 'nothing is ever deleted'); }
    ok($threw, 'service refuses any DELETE request at the lowest level');

    // ---- mapping
    $clientA = Client::create(['tenant_id' => $tenantA->id, 'name' => 'Asha', 'phone' => '255700000009', 'email' => 'asha@example.test', 'status' => 'active']);
    $r = app(LinodeController::class)->map(bind(['client_id' => $clientA->id]), $web1);
    ok($r->getStatusCode() === 200 && $web1->fresh()->client_id === $clientA->id, 'map to own client works');

    // ---- tenant B isolation
    $tenantB = Tenant::withoutGlobalScopes()->where('id', '!=', $tenantA->id)->whereHas('users')->first()
        ?? Tenant::withoutGlobalScopes()->where('id', '!=', $tenantA->id)->firstOrFail();
    $userB = User::withoutGlobalScopes()->where('tenant_id', $tenantB->id)->firstOrFail();
    auth()->login($userB);
    $clientB = Client::create(['tenant_id' => $tenantB->id, 'name' => 'Other', 'phone' => '255700000008', 'email' => 'o@example.test', 'status' => 'active']);
    auth()->login($userA);
    $r = app(LinodeController::class)->map(bind(['client_id' => $clientB->id]), $web1);
    ok($r->getStatusCode() === 422, 'mapping to another tenant client refused');

    auth()->login($userB);
    ok(LinodeAccount::count() === 0 && LinodeResource::count() === 0, 'tenant B sees no accounts/resources of A');
    ok(count(j(app(LinodeController::class)->accounts())['data']) === 0 && count(j(app(LinodeController::class)->servers())['data']) === 0, 'tenant B list endpoints empty');
    ok(LinodeAccount::find($acct->id) === null && LinodeResource::find($web1->id) === null, 'tenant B cannot resolve A ids (route binding 404)');
    $r = app(LinodeController::class)->storeDomain(bind(['account_id' => $acct->id, 'domain' => 'stolen.com']));
    ok(false, 'unreachable');
} catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
    ok(true, 'tenant B storeDomain against A account -> ModelNotFound (404)');
} catch (\Throwable $e) {
    $fail++; echo 'FAIL exception ' . $e->getMessage() . ' @' . $e->getFile() . ':' . $e->getLine() . "\n";
}

try {
    auth()->login($userA);
    // audit + logs never contain token
    $audits = json_encode(LinodeAuditLog::all()->toArray());
    ok(!str_contains($audits, TOKEN) && !str_contains($audits, 'SECRET'), 'token absent from audit logs');
    ok(LinodeAuditLog::where('action', 'domain.create')->exists() && LinodeAuditLog::where('action', 'record.create')->count() >= 2, 'writes are audited');
    ok(!str_contains(json_encode($logged), 'SECRET'), 'token absent from app log');

    // permission gating
    $noPerm = User::withoutGlobalScopes()->whereNotNull('role_id')->limit(300)->get()->first(fn ($u) => !$u->isSuperAdmin() && !$u->hasAnyPermission(['linode.manage']));
    if ($noPerm) {
        $rq = Request::create('/x'); $rq->setUserResolver(fn () => $noPerm);
        $res = (new CheckPermission())->handle($rq, fn () => response('ok'), 'linode.manage');
        ok($res->getStatusCode() === 403, 'user without linode.manage gets 403');
    } else { echo "SKIP no user without linode.manage found\n"; }
    $adminHas = DB::table('permissions')->whereIn('name', ['menu.linode', 'linode.read', 'linode.manage'])->count() === 3;
    ok($adminHas, 'permissions seeded');
} catch (\Throwable $e) {
    $fail++; echo 'FAIL exception ' . $e->getMessage() . ' @' . $e->getLine() . "\n";
}
DB::rollBack();
echo $fail ? "$fail FAILED\n" : "ALL PASSED\n";
exit($fail ? 1 : 0);

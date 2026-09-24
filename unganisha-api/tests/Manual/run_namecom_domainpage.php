<?php
// php tests/Manual/run_namecom_domainpage.php  (live DB rolled back; Name.com AND FRED fully faked, Http::preventStrayRequests - NO real calls)
require __DIR__ . '/../../vendor/autoload.php';
$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Exceptions\NameComApiException;
use App\Http\Controllers\{DomainController};
use App\Http\Controllers\Portal\PortalDomainController;
use App\Models\{Client, ClientUser, Domain, DomainLog, NameComAccount, Tenant, User};
use App\Services\Registrar\{NameComDriver, NameComDomainService};
use Illuminate\Http\Request;
use Illuminate\Support\Facades\{Artisan, DB, Http, Log};

const TOK = 'nc_PAGE_TOKEN_pppppppppppppppppppppppp9999';
NameComDriver::$sleepOnRateLimit = false;
$fail = 0;
function ok($c, $m) { global $fail; if (!$c) { $fail++; echo "FAIL $m\n"; } else echo "PASS $m\n"; }
function fk($x) { Http::swap(new \Illuminate\Http\Client\Factory()); Http::preventStrayRequests(); Http::fake($x); }
function j($r) { return $r->getData(true); }
function urls(): array { return Http::recorded()->map(fn ($p) => $p[0]->method() . ' ' . $p[0]->url())->values()->all(); }
function req(Request $rq, $u) { $rq->setUserResolver(fn () => $u); app()->instance('request', $rq); auth()->setUser($u); return $rq; }
function trap(callable $f) {
    try { return $f(); }
    catch (\Symfony\Component\HttpKernel\Exception\HttpException $e) { return response()->json(['message' => $e->getMessage()], $e->getStatusCode()); }
    catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) { return response()->json(['message' => 'not found'], 404); }
}
function dom(string $name, array $extra = []) {
    return array_merge(['domainName' => $name, 'createDate' => '2020-01-05T10:00:00Z', 'expireDate' => '2031-03-04T10:00:00Z', 'locked' => true, 'autorenewEnabled' => true,
        'privacyEnabled' => false, 'locks' => ['clientTransferProhibited'], 'nameservers' => ['ns1.name.com', 'ns2.name.com']], $extra);
}

DB::beginTransaction();
try {
    $tenantA = Tenant::withoutGlobalScopes()->where('name', 'MoBilling Test Co')->firstOrFail();
    $tenantB = Tenant::withoutGlobalScopes()->where('id', '!=', $tenantA->id)->firstOrFail();
    $staffA = User::withoutGlobalScopes()->where('tenant_id', $tenantA->id)->firstOrFail();
    auth()->setUser($staffA);
    NameComAccount::withoutGlobalScopes()->where('tenant_id', $tenantA->id)->delete();
    $acc = NameComAccount::create(['tenant_id' => $tenantA->id, 'label' => 'Ofisi Kuu Acct', 'is_default' => true, 'username' => 'ofisi', 'token' => TOK, 'token_hint' => '9999', 'status' => 'active']);
    $accB = NameComAccount::create(['tenant_id' => $tenantA->id, 'label' => 'Second Acct', 'is_default' => false, 'username' => 'second', 'token' => TOK . 'b', 'token_hint' => '999b', 'status' => 'active']);

    $logged = [];
    Log::listen(function ($e) use (&$logged) { $logged[] = $e->message . json_encode($e->context); });

    $client = Client::create(['name' => 'NC Page Client TEST', 'phone' => '255700000501', 'email' => 'ncpage@example.test', 'status' => 'active']);
    $nc = Domain::create(['client_id' => $client->id, 'name' => 'page-test-nc.com', 'status' => 'active', 'expires_at' => '2027-01-01', 'auto_renew' => false,
        'meta' => ['unmanaged' => true, 'namecom' => ['account_id' => $accB->id, 'nameservers' => ['old.ns1.com', 'old.ns2.com'], 'original_nameservers' => ['old.ns1.com']]]]);
    $legacy = Domain::create(['client_id' => $client->id, 'name' => 'page-test-legacy.com', 'status' => 'active', 'meta' => ['unmanaged' => true, 'namecom' => ['nameservers' => []]]]);
    $unm = Domain::create(['client_id' => $client->id, 'name' => 'page-test-unm.org', 'status' => 'active', 'meta' => ['unmanaged' => true]]);
    $ordered = Domain::create(['client_id' => $client->id, 'name' => 'page-test-ord.net', 'status' => 'pending', 'meta' => ['unmanaged' => true, 'registrar' => 'namecom', 'awaiting_manual_registration' => true]]);
    $tz = Domain::create(['client_id' => $client->id, 'name' => 'page-test-real.co.tz', 'status' => 'active', 'expires_at' => '2027-01-01', 'meta' => []]);

    $staffCall = fn (string $m, Domain $d) => trap(fn () => app(DomainController::class)->$m($d));

    // ---------- page resource ----------
    fk(['api.name.com/*' => Http::response(dom('page-test-nc.com'))]);
    $r = j($staffCall('registrarInfo', $nc))['data'];
    $f = $r['facts'];
    ok($r['provider'] === 'namecom' && $r['label'] === 'Second Acct' && $r['linked'] === true, 'registrar-info: provider + the domain own account LABEL (meta.account_id)');
    ok($f['expires_at'] === '2031-03-04' && $f['created_at'] === '2020-01-05' && $f['locked'] === true && $f['autorenew'] === true && $f['privacy'] === false && $f['nameservers'] === ['ns1.name.com', 'ns2.name.com'] && $f['locks'] === ['clientTransferProhibited'], 'live facts: expiry, created, locked, autorenew, privacy, nameservers, locks (only real API fields)');
    ok(!array_key_exists('registrant_handle', $r) && !array_key_exists('nsset_handle', $r) && !isset($r['facts']['registrant']), 'no FRED registry fields in the Name.com page payload');
    ok(count(urls()) === 1 && str_starts_with(urls()[0], 'GET ') && Http::recorded()->first()[0]->header('Authorization')[0] === 'Basic ' . base64_encode('second:' . TOK . 'b'), 'one read-only GET, with THAT account credentials');
    ok(!str_contains(json_encode($r), TOK) && !str_contains(json_encode($r), 'token'), 'response has no token');

    fk(['api.name.com/*' => Http::response(dom('page-test-legacy.com'))]);
    $r = j($staffCall('registrarInfo', $legacy))['data'];
    ok($r['label'] === 'Ofisi Kuu Acct' && $r['facts']['locked'] === true, 'legacy link (no account_id) falls back to the default account label');

    fk(['api.name.com/*' => Http::response(['expireDate' => '2031-03-04T00:00:00Z', 'domainName' => 'page-test-nc.com'])]);
    $f = j($staffCall('registrarInfo', $nc))['data']['facts'];
    ok($f['locked'] === null && $f['autorenew'] === null && $f['privacy'] === null && $f['nameservers'] === [], 'fields Name.com does not return stay null (never guessed)');

    fk(['api.name.com/*' => Http::response(['message' => 'boom'], 500)]);
    $resp = $staffCall('registrarInfo', $nc); $r = j($resp)['data'];
    ok($resp->getStatusCode() === 200 && $r['facts'] === null && str_contains($r['error'], 'Name.com') && $r['label'] === 'Second Acct', 'Name.com failure: page still gets 200 + graceful error + label');
    ok(!str_contains(json_encode($r), TOK), 'failure text has no token');
    fk(['*' => Http::response([], 200)]);
    $r = j($staffCall('registrarInfo', $tz))['data'];
    ok($r['provider'] === 'fred' && $r['facts'] === null && count(urls()) === 0, '.tz domain: provider fred, no Name.com call');
    $r = j($staffCall('registrarInfo', $unm))['data'];
    ok($r['provider'] === 'namecom' ? false : true, 'unmanaged non-namecom domain is not treated as Name.com');
    $r = j($staffCall('registrarInfo', $ordered))['data'];
    ok($r['provider'] === 'namecom' && $r['facts'] === null && $r['error'] && count(urls()) === 0, 'ordered-but-unlinked: no call, explanatory error');

    // ---------- Sync from Name.com refreshes + logs ----------
    fk(['api.name.com/*' => Http::response(dom('page-test-nc.com', ['expireDate' => '2029-06-30T00:00:00Z', 'nameservers' => ['ns9.name.com', 'ns8.name.com'], 'privacyEnabled' => true]))]);
    $before = DomainLog::where('domain_id', $nc->id)->count();
    $resp = trap(fn () => app(DomainController::class)->sync($nc));
    $fresh = $nc->fresh();
    ok($resp->getStatusCode() === 200 && $fresh->expires_at->toDateString() === '2029-06-30' && $fresh->status === 'active' && $fresh->meta['namecom']['nameservers'] === ['ns9.name.com', 'ns8.name.com'] && $fresh->meta['namecom']['privacy'] === true && $fresh->meta['namecom']['account_id'] === $accB->id, 'sync refreshes expiry, nameservers, privacy; keeps account_id');
    $log = DomainLog::where('domain_id', $nc->id)->where('action', 'namecom_synced')->latest()->first();
    ok(DomainLog::where('domain_id', $nc->id)->count() === $before + 1 && $log && $log->status === 'success' && $log->request['to']['expires_at'] === '2029-06-30' && $log->request['from']['expires_at'] === '2027-01-01', 'sync writes an activity log row (from/to expiry)');
    ok(count(urls()) === 1 && str_starts_with(urls()[0], 'GET ') && !DomainLog::where('domain_id', $nc->id)->where('action', 'like', '%/info/%')->exists(), 'sync = one GET at Name.com, no FRED call/log');
    fk(['api.name.com/*' => Http::response(['message' => 'x'], 500)]);
    $resp = trap(fn () => app(DomainController::class)->sync($nc));
    $l2 = DomainLog::where('domain_id', $nc->id)->where('action', 'namecom_synced')->latest('created_at')->get()->firstWhere('status', 'failed');
    ok($resp->getStatusCode() === 422 && $nc->fresh()->expires_at->toDateString() === '2029-06-30' && $l2 && !str_contains((string) $l2->error, TOK), 'failed sync: 422, data untouched, failed log row without token');

    // ---------- FRED registry sync skips Name.com / unmanaged, still does real .tz ----------
    // isolate: every other live domain is closed INSIDE this rolled-back transaction so the command sees only test rows
    Domain::withoutGlobalScopes()->whereNotIn('id', [$nc->id, $legacy->id, $unm->id, $ordered->id, $tz->id])->update(['status' => 'cancelled']);
    $tzOnlyNc = Domain::create(['client_id' => $client->id, 'name' => 'page-test-weird.co.tz', 'status' => 'active', 'meta' => ['namecom' => ['nameservers' => []]]]);
    fk(['*' => Http::response(['detail' => 'HTTP 502 simulated'], 502)]); // any FRED call would land here and be visible
    Artisan::call('domains:sync');
    $u = urls();
    $fredInfo = array_values(array_filter($u, fn ($x) => str_contains($x, '/info/')));
    ok(count($fredInfo) === 1 && str_contains($fredInfo[0], 'page-test-real.co.tz'), 'domains:sync looks up ONLY the real .tz domain at the registry (' . json_encode($fredInfo) . ')');
    ok(!array_filter($u, fn ($x) => str_contains($x, 'name.com') || str_contains($x, 'page-test-nc') || str_contains($x, 'page-test-legacy') || str_contains($x, 'page-test-unm') || str_contains($x, 'page-test-ord') || str_contains($x, 'page-test-weird')), 'no registry/Name.com calls for namecom, legacy-linked, unmanaged com/org, ordered or namecom-meta rows');
    ok(!DomainLog::whereIn('domain_id', [$nc->id, $legacy->id, $unm->id, $ordered->id, $tzOnlyNc->id])->where('action', 'like', '%/info/%')->exists(), 'no new "Registry sync check" rows for those domains');
    ok(DomainLog::where('domain_id', $tz->id)->where('action', 'like', '%/info/%')->where('status', 'failed')->exists(), 'real .tz domain still gets its registry check (logged)');
    ok($nc->fresh()->expires_at->toDateString() === '2029-06-30', 'Name.com domain expiry untouched by the registry sync');

    // post-action job hook
    fk(['*' => Http::response(['detail' => 'sim'], 502)]);
    $job = new class extends \App\Jobs\Domains\BaseDomainJob { public function go(Domain $d) { $this->syncFromRegistry($d); } };
    $job->go($nc); $job->go($unm); $job->go($tzOnlyNc);
    ok(count(urls()) === 0, 'post-action registry sync is a no-op for Name.com-linked domains');
    $job->go($tz);
    ok(count(array_filter(urls(), fn ($x) => str_contains($x, 'page-test-real.co.tz/info/'))) === 1, 'post-action registry sync still runs for real .tz');

    // ---------- portal privacy: nothing Name.com leaks to clients ----------
    $cu = ClientUser::create(['client_id' => $client->id, 'tenant_id' => $tenantA->id, 'name' => 'U pg', 'email' => 'nc-page-u@example.test', 'password' => 'x-Secret-123', 'role' => 'admin', 'is_active' => true]);
    DomainLog::create(['tenant_id' => $tenantA->id, 'domain_id' => $nc->id, 'action' => 'namecom_linked', 'request' => ['account' => 'Second Acct'], 'status' => 'success']);
    fk(['*' => Http::response([], 200)]);
    $pr = fn (string $m, ...$a) => trap(function () use ($cu, $m, $a) { $rq = req(Request::create('/p', 'GET'), $cu); return app(PortalDomainController::class)->$m($rq, ...$a); });
    $blob = json_encode([j($pr('index')), j($pr('show', $nc)), j($pr('show', $legacy))]);
    ok(!preg_match('/name\.com|namecom|Second Acct|Ofisi Kuu|usd|ns9\.name|account_id/i', $blob), 'portal list/show/activity for a Name.com domain contain no name.com / namecom / account label / USD');
    ok(str_contains($blob, 'Domain updated') && !str_contains($blob, 'Synced from Name.com'), 'portal activity shows neutral wording');
    auth()->setUser($staffA);

    // ---------- tenant isolation ----------
    $other = User::withoutGlobalScopes()->where('tenant_id', $tenantB->id)->first();
    if ($other) {
        fk(['*' => Http::response([], 200)]);
        auth()->setUser($other); req(Request::create('/x', 'GET'), $other);
        $found = Domain::where('id', $nc->id)->first();
        ok($found === null && count(urls()) === 0, 'tenant B cannot resolve tenant A Name.com domain (route binding scope), no HTTP');
        auth()->setUser($staffA);
    } else echo "SKIP no tenant B user\n";

    // route wiring
    $route = collect(app('router')->getRoutes())->first(fn ($r) => $r->uri() === 'api/domains/{domain}/registrar-info');
    ok($route && in_array('permission:domains.read', $route->gatherMiddleware()) && collect($route->gatherMiddleware())->contains(fn ($m) => str_contains($m, 'throttle:30,1,staff-domain-registrar-info')), 'registrar-info route: domains.read + its own throttle bucket');
    ok(!str_contains(implode("\n", $logged), TOK), 'token never appears in application logs');
} catch (\Throwable $e) {
    $fail++; echo "EXCEPTION: " . $e->getMessage() . "\n" . $e->getFile() . ':' . $e->getLine() . "\n";
} finally {
    DB::rollBack();
}
echo $fail ? "\n$fail FAILED\n" : "\nALL PASSED\n";
exit($fail ? 1 : 0);
